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

  /// Envoie un SOS (position + description) dans la collection `reports`.
  static Future<void> sendReport({
    required double lat,
    required double lng,
    required String description,
    String senderPhone = 'anon',
  }) async {
    await client.collection('reports').create(body: {
      'senderPhone': senderPhone,
      'position': {'lat': lat, 'lng': lng},
      'description': description,
      'status': 'open',
    });
  }

  /// Liste les SOS ouverts, avec leur position.
  static Future<List<Map<String, dynamic>>> listReports() async {
    final res = await client.collection('reports').getList(perPage: 200);
    return res.items.map((r) {
      final pos = r.data['position'];
      double? lat, lng;
      if (pos is Map) {
        lat = (pos['lat'] as num?)?.toDouble();
        lng = (pos['lng'] as num?)?.toDouble();
      }
      return {
        'id': r.id,
        'lat': lat,
        'lng': lng,
        'description': r.data['description']?.toString() ?? '',
        'status': r.data['status']?.toString() ?? '',
      };
    }).where((m) => m['lat'] != null && m['lng'] != null).toList();
  }

  /// Déclare un street medic disponible dans la collection `medics`.
  static Future<void> setMedicOnDuty({
    required double lat,
    required double lng,
    String name = 'Street Medic',
  }) async {
    await client.collection('medics').create(body: {
      'name': name,
      'phone': 'phone-${DateTime.now().millisecondsSinceEpoch}',
      'position': {'lat': lat, 'lng': lng},
      'available': true,
    });
  }

  /// Liste les medics disponibles, avec leur position.
  static Future<List<Map<String, dynamic>>> listMedics() async {
    final res = await client.collection('medics').getList(perPage: 200);
    return res.items.map((r) {
      final pos = r.data['position'];
      double? lat, lng;
      if (pos is Map) {
        lat = (pos['lat'] as num?)?.toDouble();
        lng = (pos['lng'] as num?)?.toDouble();
      }
      return {
        'id': r.id,
        'lat': lat,
        'lng': lng,
        'name': r.data['name']?.toString() ?? 'Medic',
        'available': r.data['available'] == true,
      };
    }).where((m) => m['lat'] != null && m['lng'] != null).toList();
  }

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
