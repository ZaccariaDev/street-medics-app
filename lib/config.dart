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
  static const String _kRadiusKm = 'alert_radius_km';
  static const String _kLang = 'app_lang';
  static const String _kOnDuty = 'on_duty';
  static const String _kMedicRecordId = 'medic_record_id';
  static const String _kPermsAsked = 'perms_asked';
  static const String _kVictimPhone = 'victim_phone';
  static const String _kMyReportId = 'my_report_id';

  /// URL du serveur PocketBase.
  ///
  /// Elle est **fixée au build** et n'apparaît nulle part dans le code ni
  /// dans les Réglages : l'IP du serveur n'est pas embarquée dans l'APK.
  ///
  ///   flutter build appbundle --release \
  ///     --dart-define=STREET_MEDICS_SERVER=http://151.80.155.14:8090/pb
  ///
  /// Sans `--dart-define`, l'URL est vide : l'app refuse de démarrer plutôt
  /// que de pointer vers une adresse codée en dur.
  static const String defaultServerUrl = String.fromEnvironment(
    'STREET_MEDICS_SERVER',
    defaultValue: '',
  );

  static String _serverUrl = defaultServerUrl;
  static String _deviceId = '';
  static String _medicName = '';
  static double _radiusKm = 2.0;
  static String _lang = '';
  static bool _onDuty = false;
  static String _medicRecordId = '';
  static bool _permsAsked = false;
  static String _victimPhone = '';
  static String _myReportId = '';

  static String get serverUrl => _serverUrl;
  static String get deviceId => _deviceId;
  static String get medicName => _medicName;
  static double get radiusKm => _radiusKm;

  /// Surcharge de langue ; vide = langue du téléphone.
  static String get langOverride => _lang;
  static bool get onDuty => _onDuty;

  /// Identifiant de la fiche `medics` de cet appareil (utilisé par le service
  /// d'arrière-plan pour mettre à jour la position).
  static String get medicRecordId => _medicRecordId;

  /// Vrai si la demande de permissions du premier lancement a déjà été faite.
  static bool get permsAsked => _permsAsked;

  /// Numéro de rappel de la personne qui demande de l'aide (optionnel).
  static String get victimPhone => _victimPhone;

  /// Id du SOS envoyé par CET appareil (vide si aucun). Sert à suivre le
  /// medecin qui arrive : tant que ce SOS est pris en charge, la carte
  /// reste accessible au patient.
  static String get myReportId => _myReportId;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(_kServerUrl) ?? defaultServerUrl;
    _deviceId = prefs.getString(_kDeviceId) ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = 'dev-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(_kDeviceId, _deviceId);
    }
    _medicName = prefs.getString(_kMedicName) ?? '';
    _radiusKm = prefs.getDouble(_kRadiusKm) ?? 2.0;
    _lang = prefs.getString(_kLang) ?? '';
    _onDuty = prefs.getBool(_kOnDuty) ?? false;
    _medicRecordId = prefs.getString(_kMedicRecordId) ?? '';
    _permsAsked = prefs.getBool(_kPermsAsked) ?? false;
    _victimPhone = prefs.getString(_kVictimPhone) ?? '';
    _myReportId = prefs.getString(_kMyReportId) ?? '';
  }

  static Future<void> setMedicName(String name) async {
    _medicName = name.trim();
    (await SharedPreferences.getInstance()).setString(_kMedicName, _medicName);
  }

  static Future<void> setRadiusKm(double km) async {
    _radiusKm = km;
    (await SharedPreferences.getInstance()).setDouble(_kRadiusKm, _radiusKm);
  }

  /// Vide = langue du téléphone.
  static Future<void> setLang(String code) async {
    _lang = code;
    (await SharedPreferences.getInstance()).setString(_kLang, _lang);
  }

  static Future<void> setOnDuty(bool v) async {
    _onDuty = v;
    (await SharedPreferences.getInstance()).setBool(_kOnDuty, _onDuty);
  }

  static Future<void> setMedicRecordId(String id) async {
    _medicRecordId = id;
    (await SharedPreferences.getInstance())
        .setString(_kMedicRecordId, _medicRecordId);
  }

  static Future<void> setPermsAsked() async {
    _permsAsked = true;
    (await SharedPreferences.getInstance()).setBool(_kPermsAsked, true);
  }

  static Future<void> setVictimPhone(String v) async {
    _victimPhone = v;
    (await SharedPreferences.getInstance()).setString(_kVictimPhone, v);
  }

  /// Mémorise l'id du SOS envoyé par cet appareil.
  static Future<void> setMyReportId(String v) async {
    _myReportId = v;
    (await SharedPreferences.getInstance()).setString(_kMyReportId, v);
  }

}