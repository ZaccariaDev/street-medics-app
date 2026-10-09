import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bg_service.dart';
import 'config.dart';
import 'l10n/app_localizations.dart';
import 'notifs.dart';
import 'pb_service.dart';
import 'perms.dart';
import 'update_dialog.dart';
import 'updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  await AppConfig.load();
  await Notifs.init();
  // Configuration du service d'arrière-plan (obligatoire avant startService).
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'foreground_service',
      channelName: 'Street Medics',
      channelDescription: 'Suivi de position du street medic en service',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(30000),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
  runApp(const StreetMedicsApp());
}

/// Bornes du monde utilisées comme contrainte de caméra.
///
/// Empêche de dézoomer au-delà de la carte : à sa plus petite taille, la carte
/// remplit au maximum l'interface disponible (plus de dézoom infini).
final LatLngBounds worldBounds = LatLngBounds(
  const LatLng(-85, -180),
  const LatLng(85, 180),
);

/// Notifie la carte qu'un SOS ou une prise de service vient d'être envoyé,
/// pour qu'elle recharge les marqueurs sans attendre.
final ValueNotifier<int> mapRefresh = ValueNotifier<int>(0);

/// Incrémenté quand l'état « en service » change (bouton « Devenir street
/// medic »). Écoute aussi `settingsChanged` pour les changements d'identité.
final ValueNotifier<int> dutyChanged = ValueNotifier<int>(0);

/// Notifie l'app qu'un changement de réglage (langue, rayon) impose un rebuild.
final ValueNotifier<int> settingsChanged = ValueNotifier<int>(0);

class StreetMedicsApp extends StatelessWidget {
  const StreetMedicsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: settingsChanged,
      builder: (context, value, child) => MaterialApp(
        onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
          useMaterial3: true,
        ),
        locale: Lang.resolve(AppConfig.langOverride),
        supportedLocales:
            Lang.supported.map((c) => Locale(c)).toList(growable: false),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _askedPerms = false;
  bool _checkedUpdate = false;
  bool _onDuty = false;

  @override
  void initState() {
    super.initState();
    _onDuty = AppConfig.onDuty;
    dutyChanged.addListener(_syncDuty);
    settingsChanged.addListener(_syncDuty);
  }

  @override
  void dispose() {
    dutyChanged.removeListener(_syncDuty);
    settingsChanged.removeListener(_syncDuty);
    super.dispose();
  }

  void _syncDuty() {
    if (!mounted) return;
    setState(() => _onDuty = AppConfig.onDuty);
    // Si le medic quitte son service alors qu'il est sur la carte, on le
    // ramène sur l'onglet SOS (la carte ne lui est plus accessible).
    if (!_onDuty && _selectedIndex == 1) {
      setState(() => _selectedIndex = 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Vérifie une mise à jour au démarrage (silencieux si rien).
    if (!_checkedUpdate) {
      _checkedUpdate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await UpdateDialog.maybeShow(context);
      });
    }
    // Demande des permissions au tout premier lancement de l'app.
    if (!_askedPerms && !AppConfig.permsAsked) {
      _askedPerms = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await AppConfig.setPermsAsked();
        if (mounted) await Perms.askDialog(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.appTitle),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          SosTab(),
          MapTab(),
          SettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          // Onglet Plan réservé aux street medics en service.
          if (i == 1 && !_onDuty) {
            showSnack(context, AppLocalizations.of(context).medicsOnly);
            return;
          }
          setState(() => _selectedIndex = i);
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.sos), label: t.tabSos),
          NavigationDestination(
            icon: Icon(_onDuty ? Icons.map : Icons.lock_outline),
            enabled: _onDuty,
            label: t.tabMap,
          ),
          NavigationDestination(
              icon: const Icon(Icons.settings), label: t.tabSettings),
        ],
      ),
    );
  }
}

/// ---------- Helpers ----------

Future<Position?> obtainPosition(BuildContext context) async {
  final t = AppLocalizations.of(context);
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (context.mounted) showSnack(context, t.locationOff);
    return null;
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    if (context.mounted) showSnack(context, t.permissionDenied);
    return null;
  }
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  } catch (e) {
    if (context.mounted) showSnack(context, '$e');
    return null;
  }
}

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Version installée de l'app (nom + numéro de build), pour les Réglages.
Future<String> _appVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${info.buildNumber})';
  } catch (_) {
    return '';
  }
}

/// Pays déduit de la carte SIM (dernier recours si la position échoue).
Future<String?> _simCountry() async {
  try {
    return await const MethodChannel('android/telephony')
        .invokeMethod<String>('getSimCountryIso');
  } catch (_) {
    return null;
  }
}

/// Pays déduit de la **position géographique** (géocodage inverse OSM).
///
/// C'est la source prioritaire : un street medic en déplacement doit obtenir
/// les numéros du pays où il se trouve réellement, pas ceux de la langue du
/// téléphone. Le résultat est mis en cache pour la session.
String? _countryCache;

Future<String?> _countryFromPosition() async {
  if (_countryCache != null) return _countryCache;
  try {
    Position? pos = await Geolocator.getLastKnownPosition();
    pos ??= await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
    ).timeout(const Duration(seconds: 6));
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'json',
      'lat': pos.latitude.toString(),
      'lon': pos.longitude.toString(),
      'zoom': '3',
    });
    final res = await http.get(uri, headers: {
      // Politique d'usage Nominatim : User-Agent identifiant obligatoire.
      'User-Agent': 'street-medics-app/1.0 (emergency app)',
    }).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final code = (body['address'] as Map?)?['country_code'];
    if (code is String && code.isNotEmpty) {
      _countryCache = code.toUpperCase();
      return _countryCache;
    }
  } catch (_) {}
  return null;
}

/// Bouton d'appel des urgences, adapté au pays courant (227 pays).
class EmergencyButton extends StatelessWidget {
  const EmergencyButton({super.key, this.compact = false});

  final bool compact;

  Future<void> _show(BuildContext context) async {
    final t = AppLocalizations.of(context);
    // Pays déterminé par la POSITION géographique (prioritaire), puis la
    // langue du téléphone, puis la carte SIM.
    final country = await _countryFromPosition() ??
        WidgetsBinding.instance.platformDispatcher.locale.countryCode ??
        await _simCountry();
    if (!context.mounted) return;
    final nums = Emergency.numbersFor(country);
    String label(List<String> types) {
      if (types.length >= 3) return t.svcAll;
      if (types.contains('ambulance')) return t.svcAmbulance;
      if (types.contains('police')) return t.svcPolice;
      if (types.contains('fire')) return t.svcFire;
      return t.svcInfo;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(t.callEmergency,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in nums)
                      ListTile(
                        leading: const Icon(Icons.phone, color: Colors.red),
                        title: Text(e.key,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        subtitle: Text(label(e.value)),
                        trailing: const Icon(Icons.call),
                        onTap: () async {
                          Navigator.pop(ctx);
                          final uri = Uri(scheme: 'tel', path: e.key);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: AppLocalizations.of(context).callEmergency,
        icon: const Icon(Icons.emergency, color: Colors.red),
        onPressed: () => _show(context),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => _show(context),
        icon: const Icon(Icons.phone_in_talk),
        label: Text(AppLocalizations.of(context).callEmergency),
      ),
    );
  }
}

/// ---------- Onglet SOS ----------

class SosTab extends StatefulWidget {
  const SosTab({super.key});

  @override
  State<SosTab> createState() => _SosTabState();
}

class _SosTabState extends State<SosTab> {
  final _descController = TextEditingController();
  final _phoneController = TextEditingController();
  Position? _lastPosition;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _phoneController.text = AppConfig.victimPhone;
  }

  @override
  void dispose() {
    _descController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendSos() async {
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    final pos = await obtainPosition(context);
    if (pos == null) {
      setState(() => _busy = false);
      return;
    }
    setState(() => _lastPosition = pos);
    try {
      final phone = _phoneController.text.trim();
      await AppConfig.setVictimPhone(phone);
      await PbService.sendReport(
        lat: pos.latitude,
        lng: pos.longitude,
        description: _descController.text.trim().isEmpty
            ? 'SOS'
            : _descController.text.trim(),
        senderPhone: phone,
      );
      if (mounted) showSnack(context, t.positionShared);
      mapRefresh.value++;
    } catch (e) {
      if (mounted) showSnack(context, '${t.errorSend} : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goOnDuty() async {
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    final pos = await obtainPosition(context);
    if (pos == null) {
      setState(() => _busy = false);
      return;
    }
    setState(() => _lastPosition = pos);

    // Vérifie les permissions nécessaires au suivi en arrière-plan : si l'une
    // manque, on la redemande avant de prendre le service.
    final missing = await Perms.missingForDuty();
    if (missing.isNotEmpty && mounted) {
      await Perms.askDialog(context, duty: true, missing: missing);
      if (!mounted) return;
      final still = await Perms.missingForDuty();
      if (still.isNotEmpty && mounted) showSnack(context, t.permMissing);
    }

    try {
      final name =
          AppConfig.medicName.isEmpty ? 'Street Medic' : AppConfig.medicName;
      final id = await PbService.setMedicOnDuty(
        lat: pos.latitude,
        lng: pos.longitude,
        deviceId: AppConfig.deviceId,
        name: name,
      );
      await AppConfig.setMedicRecordId(id);
      await AppConfig.setOnDuty(true);
      await startBackgroundService();
      dutyChanged.value++;
      if (mounted) showSnack(context, t.onDutyMsg);
      mapRefresh.value++;
    } catch (e) {
      if (mounted) showSnack(context, '${t.errorSend} : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Affiche l'engagement du street medic : certificat sur l'honneur avant
  /// de prendre le service. Le bouton n'est actif qu'après lecture confirmée.
  Future<void> _confirmAndGoOnDuty() async {
    final t = AppLocalizations.of(context);
    var accepted = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          icon: const Icon(Icons.health_and_safety, color: Colors.red),
          title: Text(t.certTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.certBody),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: accepted,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(t.certCheck),
                  onChanged: (v) => setLocal(() => accepted = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t.cancel),
            ),
            FilledButton(
              onPressed: accepted
                  ? () {
                      Navigator.pop(ctx);
                      _goOnDuty();
                    }
                  : null,
              child: Text(t.certAccept),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _goOffDuty() async {
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    try {
      await PbService.setMedicOffDuty(AppConfig.deviceId);
      await AppConfig.setOnDuty(false);
      await stopBackgroundService();
      dutyChanged.value++;
      if (mounted) showSnack(context, t.offDutyMsg);
      mapRefresh.value++;
    } catch (e) {
      if (mounted) showSnack(context, '${t.errorSend} : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.emergency, size: 64, color: Colors.red),
          const SizedBox(height: 10),
          Text(t.needHelp,
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(t.sosExplain, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          TextField(
            controller: _descController,
            decoration: InputDecoration(
              labelText: t.descriptionOptional,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: t.victimPhone,
              helperText: t.victimPhoneHint,
              prefixIcon: const Icon(Icons.phone),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _busy ? null : _sendSos,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sos),
              label: Text(_busy ? t.sending : t.sendMyPosition),
            ),
          ),
          const SizedBox(height: 12),
          const EmergencyButton(),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _confirmAndGoOnDuty,
              icon: const Icon(Icons.medical_services),
              label: Text(t.becomeMedic),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _goOffDuty,
            child: Text(t.endService),
          ),
          if (AppConfig.onDuty)
            Text(t.trackingOn,
                style: const TextStyle(fontSize: 12, color: Colors.green)),
          if (_lastPosition != null) ...[
            const SizedBox(height: 8),
            Text(
              '${_lastPosition!.latitude.toStringAsFixed(5)}, '
              '${_lastPosition!.longitude.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}

/// ---------- Service d'arrière-plan ----------

Future<void> startBackgroundService() async {
  final cfg = jsonEncode({
    'base': AppConfig.serverUrl,
    'deviceId': AppConfig.medicRecordId,
    'medicName': AppConfig.medicName,
    'radiusKm': AppConfig.radiusKm,
  });
  await FlutterForegroundTask.saveData(key: 'cfg', value: cfg);

  final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
  if (notifPerm != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }
  await Notifs.requestPermissions();

  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.restartService();
  } else {
    await FlutterForegroundTask.startService(
      serviceId: 101,
      serviceTypes: [
        ForegroundServiceTypes.location,
        ForegroundServiceTypes.dataSync,
      ],
      notificationTitle: 'Street Medics',
      notificationText: 'Suivi de position actif',
      callback: startCallback,
    );
  }
}

Future<void> stopBackgroundService() async {
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.stopService();
  }
}

/// ---------- Onglet Carte ----------

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  final MapController _mapController = MapController();
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _medics = [];
  LatLng? _myPosition;
  bool _loading = false;
  Timer? _autoTimer;

  /// Blips traités encore affichés quelques secondes (grisés) avant de
  /// disparaître : le medic voit sa confirmation, puis le marqueur s'efface.
  final List<Map<String, dynamic>> _fading = [];
  final List<Timer> _fadeTimers = [];

  /// Durée d'affichage d'un blip traité avant disparition.
  static const Duration _fadeDelay = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _refresh();
    _locate();
    mapRefresh.addListener(_refresh);
    _autoTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    for (final t in _fadeTimers) {
      t.cancel();
    }
    mapRefresh.removeListener(_refresh);
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _mapController.dispose();
    super.dispose();
  }

  /// Reçoit les alertes du service d'arrière-plan et les affiche.
  void _onTaskData(Object data) {
    if (data is Map && data['type'] == 'sos_alert') {
      final dKm = (data['distanceKm'] as num?)?.toDouble() ?? 0;
      final dist = dKm < 1
          ? '${(dKm * 1000).round()} m'
          : '${dKm.toStringAsFixed(1)} km';
      if (mounted) {
        final t = AppLocalizations.of(context);
        showSnack(context, '${t.nearSos} ($dist)');
      }
      _refresh();
    }
  }

  Future<void> _locate() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() => _myPosition = LatLng(pos.latitude, pos.longitude));
        _mapController.move(_myPosition!, 14);
      }
    } catch (_) {}
  }

  Future<void> _centerOnMe() async {
    if (_myPosition != null) {
      _mapController.move(_myPosition!, 17);
      return;
    }
    final pos = await obtainPosition(context);
    if (pos == null) return;
    final here = LatLng(pos.latitude, pos.longitude);
    if (mounted) {
      setState(() => _myPosition = here);
      _mapController.move(here, 17);
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final reports = await PbService.listReports();
      final medics = await PbService.listMedics();
      if (mounted) {
        setState(() {
          _reports = reports;
          _medics = medics;
        });
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _badge(IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Icon(icon, color: color, size: 26),
    );
  }

  /// Ouvre l'itinéraire vers un SOS dans une application de navigation.
  ///
  /// L'app choisie calcule elle-même le trajet le plus court et guide le
  /// medic : la destination est déjà remplie, rien à saisir.
  Future<void> _navigateTo(BuildContext context, Map<String, dynamic> r) async {
    final t = AppLocalizations.of(context);
    final lat = (r['lat'] as num).toDouble();
    final lng = (r['lng'] as num).toDouble();
    final coords = '$lat,$lng';

    // Tente d'ouvrir une URL ; renvoie true si une app a répondu.
    Future<bool> tryOpen(Uri uri) async {
      try {
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
      return false;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t.navigateTitle,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            // Google Maps : navigation directe en voiture.
            ListTile(
              leading: const Icon(Icons.map, color: Colors.blue),
              title: const Text('Google Maps'),
              onTap: () async {
                Navigator.pop(ctx);
                if (!await tryOpen(
                    Uri.parse('google.navigation:q=$coords&mode=d'))) {
                  await tryOpen(Uri.parse(
                      'https://www.google.com/maps/dir/?api=1'
                      '&destination=$coords&travelmode=driving'));
                }
              },
            ),
            // Waze : navigation directe.
            ListTile(
              leading: const Icon(Icons.navigation, color: Colors.lightBlue),
              title: const Text('Waze'),
              onTap: () async {
                Navigator.pop(ctx);
                if (!await tryOpen(
                    Uri.parse('waze://?ll=$coords&navigate=yes'))) {
                  await tryOpen(Uri.parse(
                      'https://waze.com/ul?ll=$coords&navigate=yes'));
                }
              },
            ),
            // Autre app : laisse Android proposer (Organic Maps, OSMAnd…).
            ListTile(
              leading: const Icon(Icons.apps, color: Colors.grey),
              title: Text(t.navigate),
              subtitle: const Text('Organic Maps, OSMAnd…'),
              onTap: () async {
                Navigator.pop(ctx);
                await tryOpen(Uri.parse('geo:$coords?q=$coords'));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Distance approximative entre le medic et un SOS, en mètres.
  double? _distanceTo(Map<String, dynamic> r) {
    final me = _myPosition;
    if (me == null) return null;
    final target = LatLng(r['lat'] as double, r['lng'] as double);
    return const Distance().as(LengthUnit.Meter, me, target);
  }

  void _showReportDetail(Map<String, dynamic> r) {
    final t = AppLocalizations.of(context);
    final status = r['status']?.toString() ?? 'open';
    final claimed = r['claimedBy']?.toString() ?? '';
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('SOS',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            Text(r['description']?.toString() ?? '',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              '${(r['lat'] as double).toStringAsFixed(5)}, '
              '${(r['lng'] as double).toStringAsFixed(5)}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              status == 'resolved'
                  ? '${t.statusResolved} $claimed'
                  : status == 'claimed'
                      ? '${t.statusClaimed} $claimed'
                      : t.statusOpen,
              style: TextStyle(
                color: status == 'open' ? Colors.orange : Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Distance approximative, si la position du medic est connue.
            if (_distanceTo(r) != null) ...[
              const SizedBox(height: 4),
              Text(
                _distanceTo(r)! < 1000
                    ? '${_distanceTo(r)!.round()} m'
                    : '${(_distanceTo(r)! / 1000).toStringAsFixed(1)} km',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
            // Trajet vers le SOS : l'app de navigation calcule le plus court.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.blue),
                icon: const Icon(Icons.directions),
                label: Text(t.shortestRoute),
                onPressed: () => _navigateTo(ctx, r),
              ),
            ),
            const SizedBox(height: 12),
            // Appeler la victime. Le numéro est masqué côté victime (appel
            // privé) : le medic reste protégé, la victime assume son numéro.
            if ((r['senderPhone'] ?? '').toString().isNotEmpty) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  icon: const Icon(Icons.phone),
                  label: Text(t.callVictim),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final uri = Uri(
                        scheme: 'tel', path: r['senderPhone'].toString());
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                ),
              ),
              const SizedBox(height: 4),
              Text(t.privateCall,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 12),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(t.noPhone,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(t.takeCharge),
                  onPressed: status == 'open'
                      ? () async {
                          Navigator.pop(ctx);
                          await _claim(r);
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.done_all),
                  label: Text(t.resolvedBtn),
                  onPressed: status != 'resolved'
                      ? () async {
                          Navigator.pop(ctx);
                          await _resolve(r['id'] as String);
                        }
                      : null,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _claim(Map<String, dynamic> r) async {
    final name =
        AppConfig.medicName.isEmpty ? 'Street Medic' : AppConfig.medicName;
    try {
      await PbService.claimReport(r['id'] as String, name);
      if (!mounted) return;
      showSnack(context, AppLocalizations.of(context).takeCharge);
      _refresh();
      // Dès qu'il accepte d'aider, on propose l'itinéraire le plus court :
      // la destination est déjà remplie, le medic n'a qu'à choisir son app.
      await _navigateTo(context, r);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  /// Marque un blip comme « traité » : il reste affiché (grisé) quelques
  /// secondes, puis disparaît de la carte.
  void _fadeOut(String reportId) {
    final r = _reports.firstWhere(
      (x) => x['id'] == reportId,
      orElse: () => <String, dynamic>{},
    );
    if (r.isNotEmpty) {
      setState(() => _fading.add({...r, 'status': 'resolved'}));
    }
    final timer = Timer(_fadeDelay, () {
      if (!mounted) return;
      setState(() => _fading.removeWhere((x) => x['id'] == reportId));
    });
    _fadeTimers.add(timer);
    // Le serveur ne renvoie plus le record : on retire aussi la copie locale.
    setState(() => _reports.removeWhere((x) => x['id'] == reportId));
  }

  Future<void> _resolve(String reportId) async {
    final name =
        AppConfig.medicName.isEmpty ? 'Street Medic' : AppConfig.medicName;
    try {
      await PbService.closeReport(reportId, name);
      if (mounted) showSnack(context, AppLocalizations.of(context).resolvedBtn);
      _fadeOut(reportId);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  void _showMedicDetail(Map<String, dynamic> m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.medical_services, color: Colors.green),
              SizedBox(width: 8),
              Text('Street medic',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            Text(m['name']?.toString() ?? 'Medic',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              '${(m['lat'] as double).toStringAsFixed(5)}, '
              '${(m['lng'] as double).toStringAsFixed(5)}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // Les signalements traités disparaissent de la carte : le serveur les
    // exclut déjà, et les blips en cours de disparition restent quelques
    // secondes (grisés) pour confirmer la prise en charge au medic.
    final active = [
      ..._reports
          .where((r) => (r['status']?.toString() ?? 'open') != 'resolved'),
      ..._fading,
    ];
    final markers = <Marker>[
      for (final r in active)
        Marker(
          point: LatLng(r['lat'] as double, r['lng'] as double),
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _showReportDetail(r),
            child: _badge(
              r['status'] == 'resolved' ? Icons.check : Icons.warning,
              r['status'] == 'resolved'
                  ? Colors.grey
                  : r['status'] == 'claimed'
                      ? Colors.orange
                      : Colors.red,
            ),
          ),
        ),
      for (final m in _medics)
        Marker(
          point: LatLng(m['lat'] as double, m['lng'] as double),
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _showMedicDetail(m),
            child: _badge(Icons.medical_services, Colors.green),
          ),
        ),
      if (_myPosition != null)
        Marker(
          point: _myPosition!,
          width: 44,
          height: 44,
          child: _badge(Icons.my_location, Colors.blue),
        ),
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(46.6, 2.4),
            initialZoom: 6,
            cameraConstraint: CameraConstraint.contain(bounds: worldBounds),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'fr.streetmedics.app',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                const Icon(Icons.warning, color: Colors.red, size: 18),
                Text(' ${_reports.length}  '),
                const Icon(Icons.medical_services,
                    color: Colors.green, size: 18),
                Text(' ${_medics.length}'),
              ]),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: const Card(child: EmergencyButton(compact: true)),
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'refresh',
                onPressed: _loading ? null : _refresh,
                tooltip: t.refresh,
                child: _loading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : const Icon(Icons.refresh),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'locate',
                onPressed: _centerOnMe,
                tooltip: t.myPosition,
                child: const Icon(Icons.my_location),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ---------- Onglet Réglages ----------

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final TextEditingController _urlController;
  late final TextEditingController _nameController;
  final _emailController = TextEditingController();
  final _pwdController = TextEditingController();
  String _status = '';
  late double _radius;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: AppConfig.serverUrl);
    _nameController = TextEditingController(text: AppConfig.medicName);
    _radius = AppConfig.radiusKm;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    await AppConfig.setServerUrl(_urlController.text);
    setState(() => _status = AppConfig.serverUrl);
  }

  Future<void> _testConnection() async {
    final t = AppLocalizations.of(context);
    await AppConfig.setServerUrl(_urlController.text);
    if (!mounted) return;
    setState(() => _status = t.test);
    final ok = await PbService.ping();
    if (!mounted) return;
    setState(() => _status = ok ? t.connectionOk : t.serverUnreachable);
  }

  Future<void> _saveName() async {
    await AppConfig.setMedicName(_nameController.text);
    setState(() => _status = AppConfig.medicName);
  }

  Future<void> _signUp() async {
    final t = AppLocalizations.of(context);
    try {
      await PbService.signUp(
          _emailController.text.trim(), _pwdController.text.trim());
      setState(() => _status = t.connectionOk);
    } catch (e) {
      setState(() => _status = '$e');
    }
  }

  Future<void> _signIn() async {
    final t = AppLocalizations.of(context);
    try {
      await PbService.signIn(
          _emailController.text.trim(), _pwdController.text.trim());
      setState(() => _status = t.connectionOk);
    } catch (e) {
      setState(() => _status = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(t.language,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: AppConfig.langOverride,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            DropdownMenuItem(value: '', child: Text(t.languageSystem)),
            for (final c in Lang.supported)
              DropdownMenuItem(value: c, child: Text(Lang.name(c))),
          ],
          onChanged: (v) async {
            await AppConfig.setLang(v ?? '');
            settingsChanged.value++;
          },
        ),
        const Divider(height: 40),
        Text(t.serverUrl,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          controller: _urlController,
          decoration: InputDecoration(
              labelText: t.serverUrl, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
                onPressed: _saveUrl, child: Text(t.save)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
                onPressed: _testConnection, child: Text(t.test)),
          ),
        ]),
        const Divider(height: 40),
        Text(t.alertRadius,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(t.alertRadiusHelp,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Row(children: [
          Expanded(
            child: Slider(
              value: _radius,
              min: 0.5,
              max: 50,
              divisions: 99,
              label: '${_radius.toStringAsFixed(1)} km',
              onChanged: (v) => setState(() => _radius = v),
              onChangeEnd: (v) async {
                await AppConfig.setRadiusKm(v);
              },
            ),
          ),
          Text('${_radius.toStringAsFixed(1)} km'),
        ]),
        const Divider(height: 40),
        Text(t.medicIdentity,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
              labelText: t.medicName, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _saveName, child: Text(t.save)),
        const Divider(height: 40),
        Text(t.permSection,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.shield_outlined),
          label: Text(t.permCheck),
          onPressed: () async {
            final t2 = AppLocalizations.of(context);
            final missing = await Perms.missingForDuty();
            if (!context.mounted) return;
            if (missing.isEmpty) {
              setState(() => _status = t2.permOk);
            } else {
              setState(() => _status = t2.permMissingShort);
              await Perms.askDialog(context, missing: missing);
            }
          },
        ),
        const Divider(height: 40),
        // Mise à jour : version installée + vérification manuelle.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.system_update),
                label: Text(t.checkUpdate),
                onPressed: () async {
                  final t2 = AppLocalizations.of(context);
                  final latest = await Updater.check();
                  if (!context.mounted) return;
                  if (latest == null) {
                    setState(() => _status = t2.upToDate);
                  } else {
                    await UpdateDialog.maybeShow(context);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<String>(
          future: _appVersion(),
          builder: (context, snap) => Text(
            '${t.version} ${snap.data ?? '…'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const Divider(height: 40),
        TextField(
          controller: _emailController,
          decoration: InputDecoration(
              labelText: t.email, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pwdController,
          obscureText: true,
          decoration: InputDecoration(
              labelText: t.password, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(onPressed: _signIn, child: Text(t.signIn)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(onPressed: _signUp, child: Text(t.signUp)),
          ),
        ]),
        if (PbService.isLoggedIn)
          TextButton(
            onPressed: () {
              PbService.logout();
              setState(() => _status = '');
            },
            child: Text(t.logOut),
          ),
        const SizedBox(height: 20),
        if (_status.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_status),
            ),
          ),
      ],
    );
  }
}
