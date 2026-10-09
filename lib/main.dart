import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import 'config.dart';
import 'pb_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
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

class StreetMedicsApp extends StatelessWidget {
  const StreetMedicsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Street Medics FR',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const MainScreen(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Street Medics FR'),
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
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sos), label: 'SOS'),
          NavigationDestination(icon: Icon(Icons.map), label: 'Carte'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Réglages'),
        ],
      ),
    );
  }
}

/// ---------- Helpers géolocalisation ----------

Future<Position?> obtainPosition(BuildContext context) async {
  // Vérifie que le service de localisation est actif.
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (context.mounted) {
      showSnack(context, 'Activez la localisation sur l\'appareil.');
    }
    return null;
  }
  // Demande la permission via geolocator (pas de plugin externe).
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    if (context.mounted) {
      showSnack(context, 'Permission de localisation refusée.');
    }
    return null;
  }
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  } catch (e) {
    if (context.mounted) {
      showSnack(context, 'Position indisponible : $e');
    }
    return null;
  }
}

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            ? 'SOS - Position partagée'
            : _descController.text.trim(),
      );
      if (mounted) {
        showSnack(context, 'Votre position a été partagée, tenez bon !');
      }
      mapRefresh.value++; // la carte recharge les marqueurs
    } catch (e) {
      if (mounted) showSnack(context, 'Échec envoi : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goOnDuty() async {
    setState(() => _busy = true);
    final pos = await obtainPosition(context);
    if (pos == null) {
      setState(() => _busy = false);
      return;
    }
    setState(() => _lastPosition = pos);
    try {
      await PbService.setMedicOnDuty(lat: pos.latitude, lng: pos.longitude);
      if (mounted) showSnack(context, 'Vous êtes en service.');
      mapRefresh.value++; // la carte recharge les marqueurs
    } catch (e) {
      if (mounted) showSnack(context, 'Échec : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emergency, size: 72, color: Colors.red),
          const SizedBox(height: 12),
          const Text(
            'Besoin d\'aide ?',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Votre position sera envoyée aux street medics à proximité.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Description (optionnel)',
              border: OutlineInputBorder(),
              hintText: 'ex : personne blessée, lieu précis…',
            ),
          ),
          const SizedBox(height: 20),
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
              label: Text(_busy ? 'Envoi…' : 'ENVOYER MA POSITION'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _goOnDuty,
              icon: const Icon(Icons.medical_services),
              label: const Text('Je suis street medic — prendre le service'),
            ),
          ),
          if (_lastPosition != null) ...[
            const SizedBox(height: 16),
            Text(
              'Dernière position : ${_lastPosition!.latitude.toStringAsFixed(5)}, '
              '${_lastPosition!.longitude.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
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

  @override
  void initState() {
    super.initState();
    _refresh();
    _locate();
    mapRefresh.addListener(_refresh);
  }

  @override
  void dispose() {
    mapRefresh.removeListener(_refresh);
    _mapController.dispose();
    super.dispose();
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
    } catch (_) {
      // silencieux : la carte reste centrée par défaut
    }
  }

  /// Recentre et zoome sur la position de l'utilisateur (façon Google Maps).
  Future<void> _centerOnMe() async {
    if (_myPosition != null) {
      _mapController.move(_myPosition!, 17);
      return;
    }
    // Position pas encore connue : on la demande.
    final pos = await obtainPosition(context);
    if (pos == null) return;
    final here = LatLng(pos.latitude, pos.longitude);
    if (mounted) {
      setState(() => _myPosition = here);
      _mapController.move(here, 17);
    }
  }

  /// Détail d'un marqueur au tap.
  void _showReportDetail(Map<String, dynamic> r) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 8),
                Text('SOS',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(r['description']?.toString() ?? '',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Position : ${(r['lat'] as double).toStringAsFixed(5)}, '
              '${(r['lng'] as double).toStringAsFixed(5)}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text('Statut : ${r['status'] ?? 'open'}',
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  /// Détail d'un medic au tap.
  void _showMedicDetail(Map<String, dynamic> m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.medical_services, color: Colors.green),
                SizedBox(width: 8),
                Text('Street medic',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(m['name']?.toString() ?? 'Medic',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Position : ${(m['lat'] as double).toStringAsFixed(5)}, '
              '${(m['lng'] as double).toStringAsFixed(5)}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(m['available'] == true ? 'En service' : 'Indisponible',
                style: TextStyle(
                    color: m['available'] == true
                        ? Colors.green
                        : Colors.grey)),
          ],
        ),
      ),
    );
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
      if (mounted) showSnack(context, 'Chargement impossible : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pastille ronde colorée pour un marqueur (plus lisible qu'une icône nue).
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

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      for (final r in _reports)
        Marker(
          point: LatLng(r['lat'] as double, r['lng'] as double),
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _showReportDetail(r),
            child: _badge(Icons.warning, Colors.red),
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
            // Empêche de dézoomer au-delà de la carte : à sa plus petite
            // taille, la carte remplit au maximum l'interface disponible.
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
          right: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red, size: 18),
                  Text(' ${_reports.length}  '),
                  const Icon(Icons.medical_services,
                      color: Colors.green, size: 18),
                  Text(' ${_medics.length}'),
                ],
              ),
            ),
          ),
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
                tooltip: 'Rafraîchir',
                child: _loading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : const Icon(Icons.refresh),
              ),
              const SizedBox(height: 12),
              // Bouton « ma position » (façon Google Maps) : recentre et
              // zoome sur la rue où se trouve l'utilisateur.
              FloatingActionButton(
                heroTag: 'locate',
                onPressed: _centerOnMe,
                tooltip: 'Ma position',
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
  final _emailController = TextEditingController();
  final _pwdController = TextEditingController();
  String _status = '';

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: AppConfig.serverUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _emailController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    await AppConfig.setServerUrl(_urlController.text);
    setState(() => _status = 'URL enregistrée : ${AppConfig.serverUrl}');
  }

  Future<void> _testConnection() async {
    await AppConfig.setServerUrl(_urlController.text);
    setState(() => _status = 'Test en cours…');
    final ok = await PbService.ping();
    setState(() => _status = ok
        ? 'Connexion OK — serveur joignable.'
        : 'Serveur injoignable. Vérifiez l\'URL et que PocketBase tourne.');
  }

  Future<void> _signUp() async {
    try {
      await PbService.signUp(
          _emailController.text.trim(), _pwdController.text.trim());
      setState(() => _status = 'Compte créé et connecté.');
    } catch (e) {
      setState(() => _status = 'Échec création : $e');
    }
  }

  Future<void> _signIn() async {
    try {
      await PbService.signIn(
          _emailController.text.trim(), _pwdController.text.trim());
      setState(() => _status = 'Connecté.');
    } catch (e) {
      setState(() => _status = 'Échec connexion : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Serveur PocketBase',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'URL du serveur auto-hébergé (ex : http://votre-serveur:8090).',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: 'URL du serveur',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saveUrl,
                child: const Text('Enregistrer'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _testConnection,
                child: const Text('Tester'),
              ),
            ),
          ],
        ),
        const Divider(height: 40),
        const Text('Compte (optionnel)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pwdController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Mot de passe',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _signIn,
                child: const Text('Se connecter'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _signUp,
                child: const Text('Créer un compte'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (PbService.isLoggedIn)
          TextButton(
            onPressed: () {
              PbService.logout();
              setState(() => _status = 'Déconnecté.');
            },
            child: const Text('Se déconnecter'),
          ),
        const Divider(height: 40),
        if (_status.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_status),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Street Medics FR — Flutter + PocketBase + OpenStreetMap.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
