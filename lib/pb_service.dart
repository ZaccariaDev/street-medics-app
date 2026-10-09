import 'package:pocketbase/pocketbase.dart';

import 'config.dart';

/// Accès au serveur PocketBase auto-hébergé.
///
/// Le client est recréé dès que l'URL change (écran Réglages) : il n'y a
/// jamais de dépendance à `localhost` ni à un tunnel adb.
class PbService {
  static PocketBase? _client;
  static String? _clientUrl;

  static PocketBase get client {
    final url = AppConfig.serverUrl;
    if (_client == null || _clientUrl != url) {
      _client = PocketBase(url);
      _clientUrl = url;
    }
    return _client!;
  }

  /// Teste la connexion au serveur : renvoie true si l'API répond sainement.
  static Future<bool> ping() async {
    try {
      final health = await client.health.check();
      return health.code == 200;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> _pos(RecordModel r) {
    final pos = r.data['position'];
    double? lat, lng;
    if (pos is Map) {
      lat = (pos['lat'] as num?)?.toDouble();
      lng = (pos['lng'] as num?)?.toDouble();
    }
    return {'id': r.id, 'lat': lat, 'lng': lng};
  }

  // ---------- SOS ----------

  /// Envoie un SOS (position + description) dans la collection `reports`.
  static Future<void> sendReport({
    required double lat,
    required double lng,
    required String description,
    String senderPhone = '',
  }) async {
    await client.collection('reports').create(body: {
      'senderPhone': senderPhone,
      'position': {'lat': lat, 'lng': lng},
      'description': description,
      'status': 'open',
    });
  }

  /// Liste les SOS **actifs** (ouverts ou pris en charge) avec position,
  /// statut, auteur de la prise en charge et numéro de rappel.
  ///
  /// Les signalements résolus sont exclus : le blip disparaît de la carte.
  static Future<List<Map<String, dynamic>>> listReports() async {
    final res = await client
        .collection('reports')
        .getList(perPage: 200, filter: 'status != "resolved"');
    return res.items.map((r) {
      final base = _pos(r);
      return {
        ...base,
        'description': r.data['description']?.toString() ?? '',
        'status': r.data['status']?.toString() ?? 'open',
        'claimedBy': r.data['claimedBy']?.toString() ?? '',
        'senderPhone': r.data['senderPhone']?.toString() ?? '',
        'created': r.get<String>('created'),
      };
    }).where((m) => m['lat'] != null && m['lng'] != null).toList();
  }

  /// Un medic prend en charge un SOS.
  static Future<void> claimReport(String reportId, String medicName) async {
    await client.collection('reports').update(reportId, body: {
      'status': 'claimed',
      'claimedBy': medicName,
      'claimedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Un medic clôt un SOS (pris en charge terminé).
  static Future<void> closeReport(String reportId, String medicName) async {
    await client.collection('reports').update(reportId, body: {
      'status': 'resolved',
      'claimedBy': medicName,
    });
  }

  // ---------- Medics ----------

  /// Crée ou met à jour la fiche medic de CET appareil (identité persistante
  /// via `deviceId`) : évite les doublons à chaque prise de service.
  /// Renvoie l'id du record créé/mis à jour.
  static Future<String> setMedicOnDuty({
    required double lat,
    required double lng,
    required String deviceId,
    String name = 'Street Medic',
  }) async {
    final existing = await _findMedicByDevice(deviceId);
    final body = {
      'name': name,
      'phone': deviceId,
      'position': {'lat': lat, 'lng': lng},
      'available': true,
      'deviceId': deviceId,
    };
    if (existing != null) {
      await client.collection('medics').update(existing, body: body);
      return existing;
    }
    final rec = await client.collection('medics').create(body: body);
    return rec.id;
  }

  /// Repasse la fiche medic de cet appareil en indisponible.
  static Future<void> setMedicOffDuty(String deviceId) async {
    final existing = await _findMedicByDevice(deviceId);
    if (existing != null) {
      // `deviceId` est renvoyé dans le corps : la règle de mise à jour du
      // serveur l'exige (garde-fou contre les écritures anonymes).
      await client.collection('medics').update(existing, body: {
        'available': false,
        'deviceId': deviceId,
      });
    }
  }

  /// Fiche medic de cet appareil, ou null s'il n'est pas en service.
  static Future<Map<String, dynamic>?> myMedic(String deviceId) async {
    final id = await _findMedicByDevice(deviceId);
    if (id == null) return null;
    final r = await client.collection('medics').getOne(id);
    return {..._pos(r), 'name': r.data['name']?.toString() ?? 'Medic',
      'available': r.data['available'] == true};
  }

  static Future<String?> _findMedicByDevice(String deviceId) async {
    final res = await client
        .collection('medics')
        .getList(page: 1, perPage: 1, filter: 'deviceId = "$deviceId"');
    if (res.items.isEmpty) return null;
    return res.items.first.id;
  }

  /// Liste les medics, avec position et disponibilité.
  static Future<List<Map<String, dynamic>>> listMedics() async {
    final res = await client.collection('medics').getList(perPage: 200);
    return res.items.map((r) {
      final base = _pos(r);
      return {
        ...base,
        'name': r.data['name']?.toString() ?? 'Medic',
        'available': r.data['available'] == true,
      };
    }).where((m) => m['lat'] != null && m['lng'] != null).toList();
  }

  // ---------- Comptes ----------

  static Future<void> signUp(String email, String password) async {
    await client.collection('users').create(body: {
      'email': email,
      'password': password,
      'passwordConfirm': password,
    });
    await client.collection('users').authWithPassword(email, password);
  }

  static Future<void> signIn(String email, String password) async {
    await client.collection('users').authWithPassword(email, password);
  }

  static bool get isLoggedIn => client.authStore.isValid;

  static void logout() => client.authStore.clear();
}
