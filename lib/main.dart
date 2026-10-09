import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bg_service.dart';
import 'config.dart';
import 'l10n/app_localizations.dart';
import 'notifs.dart';
import 'pb_service.dart';
import 'perms.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.sos), label: t.tabSos),
          NavigationDestination(icon: const Icon(Icons.map), label: t.tabMap),
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

/// Bouton d'appel des urgences, adapté au pays courant (227 pays).
class EmergencyButton extends StatelessWidget {
  const EmergencyButton({super.key, this.compact = false});

  final bool compact;

  Future<void> _show(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final country =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode;
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
  Position? _lastPosition;
  bool _busy = false;

  @override
  void dispose() {
    _descController.dispose();
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
      await PbService.sendReport(
        lat: pos.latitude,
        lng: pos.longitude,
        description: _descController.text.trim().isEmpty
            ? 'SOS'
            : _descController.text.trim(),
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
      if (mounted) showSnack(context, t.onDutyMsg);
      mapRefresh.value++;
    } catch (e) {
      if (mounted) showSnack(context, '${t.errorSend} : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goOffDuty() async {
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    try {
      await PbService.setMedicOffDuty(AppConfig.deviceId);
      await AppConfig.setOnDuty(false);
      await stopBackgroundService();
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
              onPressed: _busy ? null : _goOnDuty,
              icon: const Icon(Icons.medical_services),
              label: Text(t.imMedic),
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
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(t.takeCharge),
                  onPressed: status == 'open'
                      ? () async {
                          Navigator.pop(ctx);
                          await _claim(r['id'] as String);
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

  Future<void> _claim(String reportId) async {
    final name =
        AppConfig.medicName.isEmpty ? 'Street Medic' : AppConfig.medicName;
    try {
      await PbService.claimReport(reportId, name);
      if (mounted) showSnack(context, AppLocalizations.of(context).takeCharge);
      _refresh();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _resolve(String reportId) async {
    final name =
        AppConfig.medicName.isEmpty ? 'Street Medic' : AppConfig.medicName;
    try {
      await PbService.closeReport(reportId, name);
      if (mounted) showSnack(context, AppLocalizations.of(context).resolvedBtn);
      _refresh();
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
    final markers = <Marker>[
      for (final r in _reports)
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
