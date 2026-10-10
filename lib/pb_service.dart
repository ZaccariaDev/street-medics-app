import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import 'config.dart';

/// Accès au serveur PocketBase auto-hébergé.
///
/// Le client est recréé dès que l'URL change (écran Réglages) : il n'y a
/// jamais de dépendance à `localhost` ni à un tunnel adb.
///
/// **Pas d'authentification** : l'accès à la carte dépend du fait d'être
/// EN SERVICE, pas d'un compte. Envoyer un SOS rend automatiquement hors
/// service (on est victime, pas secouriste).
class PbService {
  static PocketBase? _client;
  static String? _clientUrl;

  static PocketBase get client {
    final url = AppConfig.serverUrl;
    if (_client == null || _clientUrl != url) {
      _client = PocketBase(url, httpClientFactory: () {
        return _RetryHttpClient();
      });
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
  ///
  /// Renvoie l'id du signalement créé : le patient le conserve pour suivre le
  /// medecin qui arrive (tant que le SOS est pris en charge, la carte reste
  /// accessible au patient).
  static Future<String> sendReport({
    required double lat,
    required double lng,
    required String description,
    String senderPhone = '',
  }) async {
    final res = await client.collection('reports').create(body: {
      'senderPhone': senderPhone,
      'position': {'lat': lat, 'lng': lng},
      'description': description,
      'status': 'open',
    });
    return res.id;
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

  /// Récupère un signalement par son id.
  static Future<Map<String, dynamic>?> getReport(String id) async {
    final r = await client.collection('reports').getOne(id);
    final base = _pos(r);
    return {
      ...base,
      'description': r.data['description']?.toString() ?? '',
      'status': r.data['status']?.toString() ?? 'open',
      'claimedBy': r.data['claimedBy']?.toString() ?? '',
      'claimedByName': r.data['claimedByName']?.toString() ?? '',
      'senderPhone': r.data['senderPhone']?.toString() ?? '',
      'created': r.get<String>('created'),
    };
  }

  /// Un medic prend en charge un SOS.
  ///
  /// `medicId` = id de la fiche medic : le patient l'utilise pour retrouver la
  /// position du medecin qui arrive (mise à jour toutes les 30 s côté serveur).
  /// `medicName` = nom affiché (stocké dans `claimedByName`).
  static Future<void> claimReport(
    String reportId,
    String medicName,
    String medicId,
  ) async {
    await client.collection('reports').update(reportId, body: {
      'status': 'claimed',
      'claimedBy': medicId,
      'claimedByName': medicName,
      'claimedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Un medic clôt un SOS (pris en charge terminé).
  static Future<void> closeReport(String reportId, String medicName) async {
    await client.collection('reports').update(reportId, body: {
      'status': 'resolved',
      'claimedBy': '',
      'claimedByName': medicName,
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
  ///
  /// Supprime la fiche auût de juste la mettre à unavailable : cela évite
  /// les doublons si le medic se remet en service plus tard.
  static Future<void> setMedicOffDuty(String deviceId) async {
    final existing = await _findMedicByDevice(deviceId);
    if (existing != null) {
      await client.collection('medics').delete(existing);
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
}

/// Client HTTP avec retry automatique pour gérer les timeouts de connexion.
///
/// Au démarrage de l'app, plusieurs requêtes API concurrentes (updater,
/// carte, géoloc) peuvent saturer la connexion et provoquer des
/// `SocketException: Connection timed out`. Ce client réessaie avec un
/// backoff exponentiel (1s, 2s, 4s) avant d'abandonner.
class _RetryHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    const maxRetries = 3;
    var attempt = 0;

    while (true) {
      try {
        final response = await _inner.send(request);
        // Si le serveur répond avec une erreur 5xx, on réessaie aussi
        if (response.statusCode >= 500 && attempt < maxRetries) {
          attempt++;
          await Future.delayed(Duration(seconds: 1 << attempt));
          continue;
        }
        return response;
      } on SocketException catch (_) {
        if (attempt >= maxRetries) rethrow;
        attempt++;
        await Future.delayed(Duration(seconds: 1 << attempt));
      } on TimeoutException catch (_) {
        if (attempt >= maxRetries) rethrow;
        attempt++;
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
  }

  @override
  void close() {
    _inner.close();
  }
}