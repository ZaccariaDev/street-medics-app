import 'package:shared_preferences/shared_preferences.dart';

/// Configuration globale de l'app Street Medics.
///
/// L'URL du serveur PocketBase est **configurable par l'utilisateur** (écran
/// Réglages) et persistée sur l'appareil. Il n'y a AUCUNE valeur `localhost` :
/// l'app est un client réseau qui parle à un serveur PocketBase auto-hébergé
/// via HTTP(S), exactement comme en production. Pas d'adb, pas d'adb reverse.
class AppConfig {
  static const String _kServerUrl = 'server_url';
  static const String _kDeviceId = 'device_id';
  static const String _kMedicName = 'medic_name';

  /// URL par défaut — serveur de TEST courant.
  /// À remplacer par l'URL du serveur déployé (modifiable dans l'onglet Réglages).
  static const String defaultServerUrl = 'http://90.93.168.208:48020/pb';

  static String _serverUrl = defaultServerUrl;
  static String _deviceId = '';
  static String _medicName = '';

  static String get serverUrl => _serverUrl;

  /// Identifiant persistant de l'appareil, utilisé pour retrouver la fiche
  /// medic de cet utilisateur (évite de créer un doublon à chaque service).
  static String get deviceId => _deviceId;

  /// Nom du street medic, utilisé sur sa fiche.
  static String get medicName => _medicName;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(_kServerUrl) ?? defaultServerUrl;
    _deviceId = prefs.getString(_kDeviceId) ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = 'dev-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(_kDeviceId, _deviceId);
    }
    _medicName = prefs.getString(_kMedicName) ?? '';
  }

  static Future<void> setServerUrl(String url) async {
    _serverUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerUrl, _serverUrl);
  }

  static Future<void> setMedicName(String name) async {
    _medicName = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMedicName, _medicName);
  }
}
