import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
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
  static const String _kSquadId = 'squad_id';
  static const String _kPermsAsked = 'perms_asked';
  static const String _kVictimPhone = 'victim_phone';
  static const String _kMyReportId = 'my_report_id';
  /// Liste des SOS envoyés par cet appareil (plusieurs signalements possibles).
  static const String _kMyReports = 'my_reports';
  static const String _kAuthEmail = 'auth_email';
  static const String _kAuthPassword = 'auth_password';

  /// URL du serveur PocketBase.
  ///
  /// Domaine Cloudflare (proxy vers ton VPS) — pas d'IP brute dans le code.
  /// Pour changer de serveur, modifie cette constante et rebuild :
  ///   flutter build appbundle --release
  static const String defaultServerUrl = 'https://api.xpertise.quest';

  static String _serverUrl = defaultServerUrl;
  static String _deviceId = '';
  static String _medicName = '';
  static double _radiusKm = 2.0;
  static String _lang = '';
  static bool _onDuty = false;
  static String _medicRecordId = '';
  static String _squadId = '';

  /// Ancien `deviceId` (format horodatage) remplacé lors de la migration.
  static String _legacyDeviceId = '';
  static bool _permsAsked = false;
  static String _victimPhone = '';

  /// SOS envoyés par cet appareil (ordre d'envoi). Peut en contenir plusieurs :
  /// en manifestation, un témoin peut signaler plusieurs blessés.
  static List<String> _myReports = <String>[];
  static String _authEmail = '';
  static String _authPassword = '';

  static String get serverUrl => _serverUrl;

  /// Vrai si une URL de serveur a été fournie au build.
  static bool get serverConfigured => _serverUrl.isNotEmpty;

  /// Affiche un bandeau rouge si le serveur n'est pas configuré.
  static bool get showServerBanner => _serverUrl.isEmpty;
  static String get deviceId => _deviceId;
  static String get medicName => _medicName;
  static double get radiusKm => _radiusKm;

  /// Surcharge de langue ; vide = langue du téléphone.
  static String get langOverride => _lang;
  static bool get onDuty => _onDuty;

  /// Identifiant de la fiche `medics` de cet appareil (utilisé par le service
  /// d'arrière-plan pour mettre à jour la position).
  static String get medicRecordId => _medicRecordId;

  /// Identifiant de l'escouade courante (collection `squads`).
  ///
  /// Vide = solo. Présent = membre d'une escouade de 2-3 medics. Utilisé
  /// pour rejoindre une escouade incomplète ou créer la sienne.
  static String get squadId => _squadId;

  /// Ancien `deviceId` (format horodatage) remplacé par l'ANDROID_ID stable.
  ///
  /// Vide si aucune migration n'a eu lieu. Permet de désactiver la fiche medic
  /// fantôme que cet identifiant avait laissée sur le serveur.
  static String get legacyDeviceId => _legacyDeviceId;

  /// Oublie l'ancien `deviceId` (sa fiche a été passée hors service).
  static void clearLegacyDeviceId() {
    _legacyDeviceId = '';
  }

  /// Vrai si la demande de permissions du premier lancement a déjà été faite.
  static bool get permsAsked => _permsAsked;

  /// Numéro de rappel de la personne qui demande de l'aide (optionnel).
  static String get victimPhone => _victimPhone;

  /// Id du SOS envoyé par CET appareil (vide si aucun). Sert à suivre le
  /// medecin qui arrive : tant que ce SOS est pris en charge, la carte
  /// reste accessible au patient.
  /// Id du PREMIER SOS envoyé par cet appareil (compatibilité ascendante).
  ///
  /// Utilisé par le service d'arrière-plan en mode patient : historiquement,
  /// un appareil n'avait qu'un SOS. Préférer `myReports` pour tout nouveau code.
  static String get myReportId => _myReports.isNotEmpty ? _myReports.first : '';

  /// Tous les SOS envoyés par cet appareil, dans l'ordre d'envoi.
  static List<String> get myReports => List<String>.unmodifiable(_myReports);

  /// Vrai si cet appareil a au moins un SOS en cours.
  static bool get hasMyReports => _myReports.isNotEmpty;

  /// Email du compte auto-généré (auth automatique).
  static String get authEmail => _authEmail;

  /// Mot de passe du compte auto-généré (auth automatique).
  static String get authPassword => _authPassword;

  /// Version de l'app (renseignée au démarrage via `PackageInfo`).
  static String appVersion = '';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(_kServerUrl) ?? defaultServerUrl;
    _deviceId = prefs.getString(_kDeviceId) ?? '';
    // Identifiant STABLE de l'appareil : `androidId` survit aux
    // réinstallations (contrairement à un timestamp en SharedPreferences).
    // Sans cela, chaque réinstallation créait une nouvelle fiche medic
    // fantôme sur la carte.
    //
    // MIGRATION : les premières versions stockaient `dev-<microsecondes>`.
    // Or cet identifiant n'était calculé QUE si la valeur était vide : un
    // appareil déjà installé gardait donc son ancien identifiant à vie, et
    // laissait une fiche fantôme de plus à chaque réinstallation. On remplace
    // désormais tout identifiant au format horodatage par l'ANDROID_ID stable.
    final isLegacy = RegExp(r'^dev-\d+$').hasMatch(_deviceId);
    if (_deviceId.isEmpty || isLegacy) {
      String stable = '';
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        stable = info.id; // ANDROID_ID
      } catch (_) {
        // Plateforme non-Android ou erreur : repli sur un aléatoire stable.
      }
      if (stable.isNotEmpty) {
        final migrated = 'dev-$stable';
        if (migrated != _deviceId) {
          // L'ancien identifiant est conservé : il permet de désactiver la
          // fiche fantôme qu'il a laissée sur le serveur (voir
          // `PbService.retireLegacyMedic`).
          if (isLegacy) _legacyDeviceId = _deviceId;
          _deviceId = migrated;
          await prefs.setString(_kDeviceId, _deviceId);
        }
      } else if (_deviceId.isEmpty) {
        _deviceId = 'dev-${DateTime.now().microsecondsSinceEpoch}';
        await prefs.setString(_kDeviceId, _deviceId);
      }
    }
    _medicName = prefs.getString(_kMedicName) ?? '';
    _radiusKm = prefs.getDouble(_kRadiusKm) ?? 2.0;
    _lang = prefs.getString(_kLang) ?? '';
    _onDuty = prefs.getBool(_kOnDuty) ?? false;
    _medicRecordId = prefs.getString(_kMedicRecordId) ?? '';
    _squadId = prefs.getString(_kSquadId) ?? '';
    _permsAsked = prefs.getBool(_kPermsAsked) ?? false;
    _victimPhone = prefs.getString(_kVictimPhone) ?? '';
    // SOS envoyés par cet appareil. On lit la nouvelle clé (liste) et, si elle
    // est absente, l'ancienne clé (un seul id) : sans cette reprise, un
    // utilisateur qui avait un SOS en cours le perdrait au redémarrage.
    final rawList = prefs.getString(_kMyReports);
    if (rawList != null && rawList.isNotEmpty) {
      try {
        _myReports = (jsonDecode(rawList) as List).map((e) => e.toString()).toList();
      } catch (_) {
        _myReports = <String>[];
      }
    } else {
      final legacy = prefs.getString(_kMyReportId) ?? '';
      _myReports = legacy.isEmpty ? <String>[] : <String>[legacy];
    }
    _authEmail = prefs.getString(_kAuthEmail) ?? '';
    _authPassword = prefs.getString(_kAuthPassword) ?? '';
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

  static Future<void> setSquadId(String id) async {
    _squadId = id;
    (await SharedPreferences.getInstance()).setString(_kSquadId, _squadId);
  }

  static Future<void> setPermsAsked() async {
    _permsAsked = true;
    (await SharedPreferences.getInstance()).setBool(_kPermsAsked, true);
  }

  static Future<void> setVictimPhone(String v) async {
    _victimPhone = v;
    (await SharedPreferences.getInstance()).setString(_kVictimPhone, v);
  }

  /// Remplace l'unique SOS par celui-ci (ancienne API, conservée pour la
  /// compatibilité : préférer `addMyReport`).
  static Future<void> setMyReportId(String v) async {
    _myReports = v.isEmpty ? <String>[] : <String>[v];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMyReportId, v);
    await _persistMyReports();
  }

  /// Ajoute un SOS à la liste des signalements de cet appareil.
  static Future<void> addMyReport(String id) async {
    if (id.isEmpty || _myReports.contains(id)) return;
    _myReports = [..._myReports, id];
    await _persistMyReports();
  }

  /// Retire un SOS de la liste (annulé ou résolu).
  static Future<void> removeMyReport(String id) async {
    if (!_myReports.contains(id)) return;
    _myReports = _myReports.where((e) => e != id).toList();
    await _persistMyReports();
  }

  /// Remplace toute la liste (après vérification auprès du serveur).
  static Future<void> setMyReports(List<String> ids) async {
    _myReports = List<String>.from(ids);
    await _persistMyReports();
  }

  static Future<void> _persistMyReports() async {
    await (await SharedPreferences.getInstance())
        .setString(_kMyReports, jsonEncode(_myReports));
  }

  /// Mémorise les credentials du compte auto-généré.
  static Future<void> setAuthCredentials(String email, String password) async {
    _authEmail = email;
    _authPassword = password;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuthEmail, email);
    await prefs.setString(_kAuthPassword, password);
  }

}