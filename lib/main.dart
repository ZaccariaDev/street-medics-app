import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'practices_tab.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mobile_number/mobile_number.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_log.dart';
import 'bg_service.dart';
import 'body_map.dart';
import 'body_map_view.dart';
import 'config.dart';
import 'first_aid.dart';
import 'l10n/app_localizations.dart';
import 'notifs.dart';
import 'pb_service.dart';
import 'perms.dart';
import 'phone_utils.dart';
import 'update_dialog.dart';
import 'updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  await AppConfig.load();
  // Renseigne la version de l'app (utilisée dans les journaux).
  try {
    final info = await PackageInfo.fromPlatform();
    AppConfig.appVersion = info.version;
  } catch (_) {}
  // Journalisation : installe les gestionnaires d'erreurs et charge les
  // traces de l'exécution PRÉCÉDENTE (conservées sur disque).
  await AppLog.init();
  // Auth automatique avant tout appel API (silencieux si échec).
  // 1. Tente de rafraîchir la session existante (token expiré mais refresh valide)
  // 2. Si échec, tente un re-login complet
  await PbService.refreshSession();
  await PbService.ensureAuth();
  // Si l'appareil vient de migrer vers un deviceId stable, on désactive la
  // fiche medic fantôme laissée par l'ancien identifiant (sinon elle
  // apparaîtrait comme un blip de plus sur la carte).
  await PbService.retireLegacyMedic(AppConfig.legacyDeviceId);
  // Envoie au serveur les erreurs/warnings des exécutions précédentes.
  AppLog.flush();
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
        debugShowCheckedModeBanner: false,
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
        home: const _HomeWithBanner(),
      ),
    );
  }
}

class _HomeWithBanner extends StatelessWidget {
  const _HomeWithBanner();
  @override
  Widget build(BuildContext context) {
    final body = const MainScreen();
    if (!AppConfig.showServerBanner) return body;
    return Scaffold(
      body: Stack(
        children: [
          body,
          Positioned(
            top: 0, left: 0, right: 0,
            child: Material(
              color: Colors.redAccent,
              elevation: 4,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Text(
                  'Serveur non configuré — veuillez redémarrer avec une URL.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
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
  bool _patientTracking = false;

  @override
  void initState() {
    super.initState();
    _onDuty = AppConfig.onDuty;
    // Le patient suit le medecin qui arrive uniquement quand son SOS est
    // pris en charge (pas quand il est encore ouvert).
    _patientTracking = false;
    dutyChanged.addListener(_syncDuty);
    settingsChanged.addListener(_syncDuty);
    // Le patient suit le medecin qui arrive : dès la prise en charge, la
    // carte se déverrouille.
    FlutterForegroundTask.addTaskDataCallback(_onMedicOnTheWay);
  }

  void _onMedicOnTheWay(Object data) {
    if (data is Map && data['type'] == 'medic_on_the_way') {
      setState(() => _patientTracking = true);
      // Déclenche un rafraîchissement de la carte pour afficher le medecin.
      mapRefresh.value++;
    }
  }

  @override
  void dispose() {
    dutyChanged.removeListener(_syncDuty);
    settingsChanged.removeListener(_syncDuty);
    FlutterForegroundTask.removeTaskDataCallback(_onMedicOnTheWay);
    super.dispose();
  }

  void _syncDuty() {
    if (!mounted) return;
    setState(() {
      _onDuty = AppConfig.onDuty;
      // Le patient suit le medecin qui arrive uniquement quand AU MOINS UN de
      // ses SOS est pris en charge (pas quand ils sont encore ouverts).
      _patientTracking = AppConfig.hasMyReports &&
          !AppConfig.onDuty &&
          _patientTracking;
    });
    // Si on n'a plus accès à la carte alors qu'on est dessus, on revient
    // sur l'onglet SOS.
    if (!_mapAllowed && _selectedIndex == 1) {
      setState(() => _selectedIndex = 0);
    }
  }

  /// La carte est accessible si on est en service OU si on est patient
  /// dont le SOS est pris en charge (on suit le medecin qui arrive).
  bool get _mapAllowed => _onDuty || _patientTracking;

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
          PracticesTab(),
          SettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          // Onglet Plan réservé aux street medics en service ET aux patients
          // dont le SOS est pris en charge.
          if (i == 1 && !_mapAllowed) {
            showSnack(context, AppLocalizations.of(context).medicsOnly);
            return;
          }
          setState(() => _selectedIndex = i);
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.sos), label: t.tabSos),
          NavigationDestination(
            icon: Icon(_mapAllowed ? Icons.map : Icons.lock_outline),
            enabled: _mapAllowed,
            label: t.tabMap,
          ),
          NavigationDestination(
              icon: const Icon(Icons.settings), label: t.tabSettings),
          NavigationDestination(
              icon: const Icon(Icons.menu_book),
              label: t.tabPractices,
              enabled: false, // grisé : contenu pas encore prêt
          ),
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

  /// Blessures localisées sur la silhouette, en cours de saisie pour le
  /// prochain SOS. Vide = parcours d'urgence inchangé (1 appui).
  final List<Injury> _injuries = <Injury>[];
  BodyView _injuriesView = BodyView.front;

  @override
  void initState() {
    super.initState();
    _phoneController.text = AppConfig.victimPhone;
    // Préremplit automatiquement avec le numéro du téléphone si disponible.
    if (AppConfig.victimPhone.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fillPhoneNumber());
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Préremplit le champ numéro avec le numéro de téléphone de l'appareil.
  Future<void> _fillPhoneNumber() async {
    try {
      final number = await MobileNumber.mobileNumber;
      if (number != null && number.isNotEmpty) {
        _phoneController.text = normalizePhone(number);
      }
    } catch (_) {
      // Permission refusée ou non disponible : l'utilisateur saisit manuellement.
    }
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
      // Envoyer un SOS, c'est être victime : on repasse OBLIGATOIREMENT hors
      // service (donc sans accès à la carte, ni aux alertes).
      if (AppConfig.onDuty) {
        try {
          await PbService.setMedicOffDuty(AppConfig.deviceId);
        } catch (_) {
          // Même si la mise à jour échoue, on ne reste pas « en service ».
        }
        await AppConfig.setOnDuty(false);
        await stopBackgroundService();
        dutyChanged.value++;
      }

      final phone = _phoneController.text.trim();
      await AppConfig.setVictimPhone(phone);
      // Les blessures du SOS sont copiees AVANT l'envoi : l'ecran de
      // confirmation doit les afficher, et la saisie est videe juste apres.
      final sentInjuries = List<Injury>.from(_injuries);
      final id = await PbService.sendReport(
        lat: pos.latitude,
        lng: pos.longitude,
        description: _descController.text.trim().isEmpty
            ? 'SOS'
            : _descController.text.trim(),
        senderPhone: phone,
        injuries: _injuries,
        injuriesView: _injuriesView,
      );
      // Le SOS est parti : on vide la saisie de blessures pour que le
      // prochain signalement reparte d'une silhouette vierge.
      if (mounted) {
        setState(() {
          _injuries.clear();
          _injuriesView = BodyView.front;
        });
      }
      // Le patient suit son SOS : la carte reste accessible tant qu'un
      // medecin l'a pris en charge (et jusqu'à ce qu'il soit résolu).
      // On AJOUTE à la liste : un témoin peut signaler plusieurs blessés.
      await AppConfig.addMyReport(id);
      // Lance le service en mode patient : alerte dès la prise en charge.
      await startBackgroundService();
      if (mounted) {
        final n = AppConfig.myReports.length;
        showSnack(context, n > 1 ? '${t.positionShared} ($n)' : t.positionShared);
      }
      mapRefresh.value++;
      dutyChanged.value++;
      // Ecran de confirmation : rappelle que le SOS est parti, et donne les
      // premiers gestes pour les blessures declarees (contenu provisoire).
      await _showSosSent(sentInjuries);
    } catch (e, st) {
      AppLog.error(e, stack: st, context: 'sendSos');
      if (mounted) showSnack(context, '${t.errorSend} : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Annule le DERNIER SOS envoyé (celui qu'on vient de créer par erreur).
  Future<void> _cancelLastSos() async {
    final reports = AppConfig.myReports;
    if (reports.isEmpty) return;
    await _cancelReport(reports.last);
  }

  /// Ouvre le sélecteur de blessures en plein écran.
  ///
  /// La silhouette n'est qu'une **aide** : tant qu'on ne l'ouvre pas, le SOS
  /// reste à un seul appui. Les blessures saisies s'attachent au prochain SOS.
  Future<void> _openBodyMap() async {
    final t = AppLocalizations.of(context);
    final injuries = List<Injury>.from(_injuries);
    var view = _injuriesView;
    // IMPORTANT : `pending` vit HORS du builder. Declare a l'interieur, il
    // serait recree a chaque reconstruction et la selection serait perdue
    // immediatement (bug attrape par le test d'integration).
    final pending = <String, String>{};
    // Page 0 = silhouette, page 1 = types de blessure pour chaque zone.
    final pageController = PageController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // Mise en page en deux etapes : silhouette d'abord, types ensuite.
          // La transition se fait par slide (PageView).
          final media = MediaQuery.of(ctx).size;

          void onZone(BodyZone zone) {
            if (pending.containsKey(zone.id)) {
              setSheet(() => pending.remove(zone.id));
              return;
            }
            // Type par défaut : on peut marquer vite, puis affiner.
            setSheet(() => pending[zone.id] = kInjuryTypes.first.id);
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: SizedBox(
              // Hauteur bornee : la silhouette occupe la place restante,
              // jamais plus que ce que la feuille peut offrir.
              height: media.height * 0.78,
              child: PageView(
                controller: pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // ═══ PAGE 1 : SILHOUETTE ═══
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(t.bodyMapTitle,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.bold)),
                          ),
                          // Bascule face / dos. Ce n'est PAS une rotation : le dos
                          // apparaît derrière la silhouette, en retrait. L'icône
                          // « flip » le dit mieux qu'une icône de personne.
                          SegmentedButton<BodyView>(
                            segments: [
                              ButtonSegment(
                                value: BodyView.front,
                                icon: const Icon(Icons.person, size: 18),
                                label: Text(t.bodyMapFront),
                              ),
                              ButtonSegment(
                                value: BodyView.back,
                                icon: const Icon(Icons.flip_to_back, size: 18),
                                label: Text(t.bodyMapBack),
                              ),
                            ],
                            selected: {view},
                            onSelectionChanged: (s) =>
                                setSheet(() => view = s.first),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Expanded : la silhouette prend exactement la place libre.
                      Expanded(
                        child: BodyMapView(
                          key: ValueKey(view),
                          view: view,
                          injuries: [
                            for (final e in pending.entries)
                              Injury(zoneId: e.key, typeId: e.value),
                          ],
                          onZoneTapped: onZone,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Indication : combien de zones sont sélectionnées.
                      Text(
                        pending.isEmpty
                            ? t.bodyMapHint
                            : '${pending.length} zone(s) sélectionnée(s)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setSheet(pending.clear),
                              child: Text(t.cancel),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: pending.isEmpty
                                  ? null
                                  : () {
                                      pageController.animateToPage(
                                        1,
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeOutCubic,
                                      );
                                    },
                              child: Text('${t.validate} (${pending.length})'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // ═══ PAGE 2 : TYPES DE BLESSURE ═══
                  Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () {
                              pageController.animateToPage(
                                0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                              );
                            },
                          ),
                          Expanded(
                            child: Text(
                              'Type de blessure',
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Liste des zones sélectionnées, chacune avec ses types.
                      Expanded(
                        child: ListView.builder(
                          itemCount: pending.length,
                          itemBuilder: (ctx, i) {
                            final entry = pending.entries.elementAt(i);
                            final zoneLabel =
                                _zoneLabel(t, view, entry.key);
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(zoneLabel,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      for (final type in kInjuryTypes)
                                        ChoiceChip(
                                          label: Text(
                                              _typeLabel(t, type.id)),
                                          selected:
                                              entry.value == type.id,
                                          onSelected: (_) => setSheet(
                                              () => pending[entry.key] =
                                                  type.id),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setSheet(pending.clear),
                              child: Text(t.cancel),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                injuries
                                  ..clear()
                                  ..addAll(pending.entries.map((e) =>
                                      Injury(
                                          zoneId: e.key,
                                          typeId: e.value)));
                                Navigator.of(ctx).pop(true);
                              },
                              child: Text('${t.validate} (${pending.length})'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (ok == true && mounted) {
      setState(() {
        _injuries
          ..clear()
          ..addAll(injuries);
        _injuriesView = view;
      });
    }
  }

  /// Libellé traduit d'une zone du corps.
  ///
  /// Une zone peut appartenir aux deux vues (les 6 parties du corps sont
  /// communes) ; on cherche donc dans la vue demandee puis dans l'autre.
  String _zoneLabel(AppLocalizations t, BodyView view, String zoneId) {
    var zone = bodyZones(view).where((z) => z.id == zoneId).firstOrNull;
    zone ??= bodyZones(BodyView.front)
        .where((z) => z.id == zoneId)
        .firstOrNull;
    zone ??= bodyZones(BodyView.back)
        .where((z) => z.id == zoneId)
        .firstOrNull;
    return _labelFor(t, zone?.labelKey ?? 'zoneHead');
  }

  /// Libellé traduit d'un type de blessure.
  String _typeLabel(AppLocalizations t, String typeId) {
    final type =
        kInjuryTypes.where((x) => x.id == typeId).firstOrNull;
    return _labelFor(t, type?.labelKey ?? 'injuryOther');
  }

  /// Liste des étapes de premiers gestes pour un type de blessure.
  List<String> _aidSteps(AppLocalizations t, String typeId) {
    final aid = firstAidFor(typeId);
    final raw = _aidFor(t, aid.stepsKey);
    return raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String _aidFor(AppLocalizations t, String key) {
    switch (key) {
      case 'aidWound':
        return t.aidWound;
      case 'aidFracture':
        return t.aidFracture;
      case 'aidBurn':
        return t.aidBurn;
      case 'aidOther':
        return t.aidOther;
      default:
        return t.aidOther;
    }
  }

  /// Écran de confirmation après l'envoi d'un SOS.
  ///
  /// Il rappelle que le SOS est parti, puis donne les **premiers gestes** pour
  /// chaque blessure déclarée. Le contenu des gestes est provisoire (stub) :
  /// l'association des street medics doit fournir la version réelle, et la
  /// mention le dit clairement plutôt que de faire passer du générique pour
  /// une consigne médicale.
  ///
  /// Un SOS sans blessure déclarée affiche seulement la confirmation : rien
  /// n'est inventé.
  Future<void> _showSosSent(List<Injury> injuries) async {
    if (!mounted) return;
    final t = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
        title: Text(t.sosSentTitle, textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.sosSentBody),
              if (injuries.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(t.whatToDo,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final inj in injuries) ...[
                  Row(
                    children: [
                      Icon(
                        firstAidFor(inj.typeId).urgent
                            ? Icons.priority_high
                            : Icons.info_outline,
                        size: 18,
                        color: firstAidFor(inj.typeId).urgent
                            ? Colors.red
                            : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${_zoneLabel(t, BodyView.front, inj.zoneId)} · '
                          '${_typeLabel(t, inj.typeId)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final step in _aidSteps(t, inj.typeId))
                    Padding(
                      padding: const EdgeInsets.only(left: 24, bottom: 2),
                      child: Text('• $step'),
                    ),
                  const SizedBox(height: 10),
                ],
                if (kFirstAidIsStub)
                  Text(t.aidStubNote,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.close),
          ),
        ],
      ),
    );
  }

  static String _labelFor(AppLocalizations t, String key) {
    switch (key) {
      case 'zoneHead':
        return t.zoneHead;
      case 'zoneShoulders':
        return t.zoneShoulders;
      case 'zoneChest':
        return t.zoneChest;
      case 'zoneBack':
        return t.zoneBack;
      case 'zoneArms':
        return t.zoneArms;
      case 'zoneLegs':
        return t.zoneLegs;
      case 'injuryWound':
        return t.injuryWound;
      case 'injuryFracture':
        return t.injuryFracture;
      case 'injuryBurn':
        return t.injuryBurn;
      case 'injuryOther':
        return t.injuryOther;
      default:
        return key;
    }
  }

  /// Ouvre la liste des SOS envoyés par cet appareil.
  ///
  /// Indispensable dès qu'il y en a plusieurs : on doit pouvoir annuler
  /// n'importe lequel (par exemple l'avant-dernier), pas seulement le dernier.
  /// Chaque ligne affiche sa description, sa position et son statut, avec un
  /// bouton d'annulation individuel.
  void _showMySosSheet() {
    if (!mounted) return;
    final t = AppLocalizations.of(context);
    final ids = AppConfig.myReports;
    if (ids.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.mySosTitle,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(t.mySosHint,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              // Chargement des détails : le nombre d'ids est déjà connu, on
              // affiche donc la liste immédiatement puis on la complète.
              Flexible(
                child: FutureBuilder<List<Map<String, dynamic>?>>(
                  future: Future.wait(
                      ids.map((e) => PbService.getReport(e))),
                  builder: (ctx2, snap) {
                    final rows =
                        snap.data ?? const <Map<String, dynamic>?>[];
                    final loading =
                        snap.connectionState != ConnectionState.done;
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: ids.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx3, i) {
                        final id = ids[i];
                        final r = i < rows.length ? rows[i] : null;
                        final desc = (r?['description'] ?? '') as String;
                        final claimedBy = (r?['claimedBy'] ?? '') as String;
                        // Blessures localisées : c'est ce qui permet de
                        // distinguer plusieurs SOS d'un coup d'œil.
                        final injuries =
                            (r?['injuries'] as List?)?.cast<Injury>() ??
                                const <Injury>[];
                        // La vue compte : « épaule gauche » ne se lit pas
                        // pareil de face et de dos.
                        final injView =
                            (r?['injuriesView'] as BodyView?) ?? BodyView.front;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            claimedBy.isNotEmpty
                                ? Icons.directions_run
                                : Icons.warning_amber,
                            color: claimedBy.isNotEmpty
                                ? Colors.orange
                                : Colors.red,
                          ),
                          title: Text(
                            desc.trim().isEmpty ? t.mySosNoDescription : desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                claimedBy.isNotEmpty
                                    ? t.mySosClaimed
                                    : (loading ? t.mySosLoading : t.mySosOpen),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: claimedBy.isNotEmpty
                                      ? Colors.orange
                                      : Colors.grey,
                                ),
                              ),
                              // Pastilles des blessures, une par zone.
                              if (injuries.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 2,
                                    children: [
                                      for (final inj in injuries)
                                        _InjuryChip(
                                          injury: inj,
                                          label: _zoneLabel(
                                              t, injView, inj.zoneId),
                                          typeLabel: _typeLabel(t, inj.typeId),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          trailing: TextButton(
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              await _cancelReport(id);
                            },
                            child: Text(t.cancel),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Annule un SOS précis de la liste.
  Future<void> _cancelReport(String reportId) async {
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    try {
      await PbService.cancelReport(reportId);
      await AppConfig.removeMyReport(reportId);
      // Le service d'arrière-plan ne tourne que s'il reste un SOS à suivre.
      if (!AppConfig.hasMyReports) {
        await stopBackgroundService();
      }
      dutyChanged.value++;
      mapRefresh.value++;
      if (mounted) {
        final n = AppConfig.myReports.length;
        showSnack(context, n > 0 ? '${t.sosCancelled} ($n)' : t.sosCancelled);
      }
    } catch (e, st) {
      AppLog.error(e, stack: st, context: 'cancelSos');
      if (mounted) showSnack(context, '${t.errorSend} : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goOnDuty() async {
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);

    // 1. Vérifier les permissions AVANT d'essayer d'obtenir la position.
    final missing = await Perms.missingForDuty();
    if (missing.isNotEmpty && mounted) {
      await Perms.askDialog(context, duty: true, missing: missing);
      if (!mounted) return;
      final still = await Perms.missingForDuty();
      if (still.isNotEmpty && mounted) {
        showSnack(context, t.permMissing);
        setState(() => _busy = false);
        return;
      }
    }

    // 2. Obtenir la position (permissions déjà accordées).
    if (!mounted) return;
    final pos = await obtainPosition(context);
    if (!mounted) return;
    if (pos == null) {
      if (mounted) showSnack(context, t.locationFailed);
      setState(() => _busy = false);
      return;
    }
    setState(() => _lastPosition = pos);

    // 3. Enregistrer le medic sur le serveur.
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
    } catch (e, st) {
      AppLog.error(e, stack: st, context: 'goOnDuty');
      if (mounted) showSnack(context, '${t.errorSend} : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Affiche l'engagement du street medic avant la prise de service.
  /// Le bouton n'est actif qu'après lecture confirmée (case cochée).
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
    } catch (e, st) {
      AppLog.error(e, stack: st, context: 'goOffDuty');
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.contact_phone, size: 18),
              label: Text(t.fillPhone),
              onPressed: _busy ? null : _fillPhoneNumber,
            ),
          ),
          const SizedBox(height: 8),
          // Localisation des blessures : OPTIONNELLE et hors du chemin du SOS.
          // On peut l'ignorer complètement — le bouton SOS reste à un appui.
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Icon(
                _injuries.isEmpty ? Icons.accessibility_new : Icons.healing,
                color: _injuries.isEmpty ? Colors.grey : Colors.red,
              ),
              title: Text(t.bodyMapTitle,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                _injuries.isEmpty
                    ? t.bodyMapAddOptional
                    : t.bodyMapInjuriesCount(_injuries.length),
                style: TextStyle(
                  fontSize: 12,
                  color: _injuries.isEmpty ? Colors.grey : Colors.red,
                ),
              ),
              trailing: _injuries.isEmpty
                  ? const Icon(Icons.add_circle_outline, color: Colors.grey)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: t.cancel,
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: _busy
                              ? null
                              : () => setState(() => _injuries.clear()),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
              onTap: _busy ? null : _openBodyMap,
            ),
          ),
          const SizedBox(height: 16),
          // Bouton SOS PRINCIPAL : un seul appui envoie un SOS (inchangé).
          // Un témoin peut appuyer plusieurs fois pour signaler plusieurs
          // blessés : chaque appui crée un signalement indépendant.
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
          // SOS déjà envoyés par cet appareil : le compteur ouvre la liste
          // détaillée (pour annuler un SOS précis, pas seulement le dernier).
          // N'apparaît qu'à partir du 1er signalement, pour ne rien ajouter au
          // parcours du premier SOS.
          if (AppConfig.hasMyReports) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _busy ? null : _showMySosSheet,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.list_alt,
                              size: 18, color: Colors.orange),
                          const SizedBox(width: 6),
                          Text(
                            t.activeSosCount(AppConfig.myReports.length),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 18, color: Colors.orange),
                        ],
                      ),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _cancelLastSos,
                  icon: const Icon(Icons.cancel, size: 18),
                  label: Text(t.cancelLastSos),
                  style: TextButton.styleFrom(foregroundColor: Colors.orange),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const EmergencyButton(),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppConfig.onDuty ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _busy
                  ? null
                  : (AppConfig.onDuty ? _goOffDuty : _confirmAndGoOnDuty),
              icon: Icon(AppConfig.onDuty ? Icons.stop : Icons.play_arrow),
              label: Text(AppConfig.onDuty ? t.endService : t.becomeMedic),
            ),
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
    // `recordId` = id de la fiche medic (URL du PATCH).
    // `deviceId` = identité de l'appareil (champ exigé par les règles serveur).
    // Ne PAS confondre les deux : écrire le record id dans le champ
    // `deviceId` casse la recherche de la fiche à la fin du service.
    'recordId': AppConfig.medicRecordId,
    'deviceId': AppConfig.deviceId,
    'medicName': AppConfig.medicName,
    'radiusKm': AppConfig.radiusKm,
    // `patientReportIds` : mode patient — surveille la prise en charge de TOUS
    // les SOS de cet appareil (un témoin peut en signaler plusieurs).
    // Présent = mode patient, absent = mode medic.
    if (AppConfig.hasMyReports)
      'patientReportIds': AppConfig.myReports,
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
  LatLng? _medicPosition;
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
    // Temps réel (SSE) : le serveur pousse les changements au lieu du
    // polling toutes les 20s. Gain majeur de scalabilité.
    _subscribeRealtime();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  /// Abonne la carte aux collections `reports` et `medics` en temps réel.
  void _subscribeRealtime() {
    PbService.subscribeReports((e) => _onRealtime(e, 'reports'));
    PbService.subscribeMedics((e) => _onRealtime(e, 'medics'));
    // Fallback : si SSE tombe, PbService lance un polling toutes les 20s.
    PbService.fallbackRefresh.addListener(_refresh);
  }

  /// Recoit un événement SSE (create/update/delete) et rafraîchit les
  /// données correspondantes. Si l'action est `create`, on re-récupère la
  /// fiche complète via `getOne` (l'événement SSE ne contient pas toujours
  /// tous les champs).
  void _onRealtime(dynamic e, String collection) {
    if (!mounted) return;
    final data = e.jsonData();
    final action = (data['action']?.toString() ?? '').toLowerCase();
    if (action == 'create' && collection == 'reports') {
      final record = data['record'];
      if (record is Map && record['id'] != null) {
        // Re-récupère la fiche complète (champs position, etc.)
        PbService.getReport(record['id'].toString()).then((r) {
          if (r != null && mounted) {
            setState(() {
              _reports = _reports.where((x) => x['id'] != r['id']).toList()
                ..add(r);
            });
          }
        });
        return;
      }
    }
    // update / delete / create incomplet → rafraîchit la liste concernée
    _refresh();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    for (final t in _fadeTimers) {
      t.cancel();
    }
    mapRefresh.removeListener(_refresh);
    PbService.fallbackRefresh.removeListener(_refresh);
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    PbService.unsubscribeAll();
    _mapController.dispose();
    super.dispose();
  }

  /// Reçoit les alertes du service d'arrière-plan et les affiche.
  void _onTaskData(Object data) {
    if (data is! Map) return;
    final type = data['type']?.toString() ?? '';
    if (type == 'sos_alert') {
      final dKm = (data['distanceKm'] as num?)?.toDouble() ?? 0;
      final dist = dKm < 1
          ? '${(dKm * 1000).round()} m'
          : '${dKm.toStringAsFixed(1)} km';
      if (mounted) {
        final t = AppLocalizations.of(context);
        showSnack(context, '${t.nearSos} ($dist)');
      }
      _refresh();
    } else if (type == 'medic_on_the_way') {
      if (mounted) {
        final t = AppLocalizations.of(context);
        showSnack(context, t.medicOnTheWay);
      }
      _refresh();
    } else if (type == 'medic_position') {
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        setState(() => _medicPosition = LatLng(lat, lng));
      }
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

  int _refreshFailCount = 0;
  static const int _maxRefreshInterval = 120;

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final reports = await PbService.listReports();
      final medics = await PbService.listMedics();
      _refreshFailCount = 0; // reset on success
      if (mounted) {
        setState(() {
          _reports = reports;
          _medics = medics;
        });
      }
    } catch (e, st) {
      _refreshFailCount++;
      // Le serveur a échoué : on invalide le cache de joignabilité pour que
      // le prochain abonnement SSE retente (sinon on resterait bloqué sur
      // « serveur injoignable » alors qu'il est revenu).
      PbService.resetServerReachable();
      // Remontée au serveur (uniquement au 1er échec de la série : évite de
      // noyer le serveur quand la connexion est durablement coupée).
      if (_refreshFailCount == 1) {
        AppLog.error(e, stack: st, context: 'mapRefresh');
      }
      // PAS de SnackBar ici : il recouvre le bouton "Terminer mon service"
      // et intercepte les taps. L'erreur est signalée par l'indicateur discret
      // dans le header de la carte (voir _buildHeader).
    } finally {
      if (mounted) setState(() => _loading = false);
      // Le polling est un FILET DE SÉCURITÉ, pas le mécanisme principal :
      //  - SSE actif → intervalle long (120 s) : le temps réel fait le travail,
      //    on ne fait qu'une vérification périodique de cohérence ;
      //  - SSE tombé → intervalle court (20 s) pour continuer à voir les
      //    changements sans temps réel.
      // L'intervalle s'allonge aussi en cas d'échecs réseau répétés.
      _autoTimer?.cancel();
      final base = PbService.realtimeConnected ? 120 : 20;
      final interval = _refreshFailCount == 0
          ? base
          : math.min(base * (1 << _refreshFailCount), _maxRefreshInterval);
      _autoTimer = Timer.periodic(Duration(seconds: interval), (_) => _refresh());
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
            // Appeler la victime : le numéro n'est JAMAIS affiché, il sert
            // uniquement au bouton d'appel. Le medic reste protégé (numéro
            // masqué côté victime).
            if ((r['senderPhone'] ?? '').toString().isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  icon: const Icon(Icons.phone),
                  label: Text(t.callVictim),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final uri =
                        Uri(scheme: 'tel', path: r['senderPhone'].toString());
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                ),
              )
            else
              Text(t.noPhone,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
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
      await PbService.claimReport(
        r['id'] as String,
        name,
        AppConfig.medicRecordId,
      );
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
      // Si c'était un des SOS de cet appareil, on ne le suit plus. On retire
      // précisément celui-ci : les autres signalements restent en cours.
      if (AppConfig.myReports.contains(reportId)) {
        await AppConfig.removeMyReport(reportId);
        dutyChanged.value++;
      }
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
      // Marker spécial : le medecin qui arrive (mode patient).
      if (_medicPosition != null)
        Marker(
          point: _medicPosition!,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _showMedicDetail({
              'name': t.medicOnTheWay,
              'lat': _medicPosition!.latitude,
              'lng': _medicPosition!.longitude,
            }),
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
  late final TextEditingController _nameController;
  String _status = '';
  late double _radius;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: AppConfig.medicName);
    _radius = AppConfig.radiusKm;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await AppConfig.setMedicName(_nameController.text);
    setState(() => _status = AppConfig.medicName);
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
        Text(t.alertRadius,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(t.alertRadiusHelp,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Row(children: [
          Expanded(
            child: Slider(
              value: _radius,
              min: 0.1,
              max: 50,
              divisions: 499,
              label: _radius < 1
                  ? '${(_radius * 1000).round()} m'
                  : '${_radius.toStringAsFixed(1)} km',
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

/// Pastille compacte résumant une blessure : partie du corps + type.
///
/// Sert dans la liste des SOS, où l'on doit distinguer plusieurs signalements
/// d'un coup d'œil. La couleur vient du type de blessure, la même que sur la
/// silhouette, pour que les deux vues se répondent.
class _InjuryChip extends StatelessWidget {
  const _InjuryChip({
    required this.injury,
    required this.label,
    required this.typeLabel,
  });

  final Injury injury;
  final String label;
  final String typeLabel;

  @override
  Widget build(BuildContext context) {
    final type = kInjuryTypes
        .where((t) => t.id == injury.typeId)
        .firstOrNull;
    final color = type?.color ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label · $typeLabel',
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}
