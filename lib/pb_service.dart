import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
      _client = PocketBase(url);
      _clientUrl = url;
    }
    return _client!;
  }

  /// Exécute un appel API avec gestion automatique des 401.
  /// Si le token est expiré → force re-login → réessaie une fois.
  static Future<T> _withAuth<T>(Future<T> Function() api) async {
    try {
      return await api();
    } catch (e) {
      if (_isUnauthorized(e)) {
        final ok = await forceReLogin();
        if (ok) return await api();
      }
      rethrow;
    }
  }

  /// Vrai si l'erreur est un 401 (token expiré ou invalide).
  static bool _isUnauthorized(Object e) {
    final msg = e.toString();
    return msg.contains('401') || msg.contains('Unauthorized') ||
        msg.contains('unauthorized');
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

  /// Authentification automatique au démarrage.
  ///
  /// 1. Si déjà authentifié (token valide) → retourne immédiatement.
  /// 2. Si creds stockés → `authWithPassword`.
  /// 3. Si 404 (compte n'existe pas) → crée le compte + sauvegarde creds.
  /// 4. Si pas de creds → génère email + mot de passe aléatoire, crée compte.
  ///
  /// Retourne true si authentifié, false sinon.
  static Future<bool> ensureAuth() async {
    // Déjà authentifié ?
    if (client.authStore.isValid) return true;

    // Creds stockés ?
    final email = AppConfig.authEmail;
    final password = AppConfig.authPassword;

    if (email.isNotEmpty && password.isNotEmpty) {
      try {
        await client.collection('users').authWithPassword(email, password);
        return true;
      } catch (_) {
        // Token expiré ou compte supprimé → on recrée
      }
    }

    // Générer un nouveau compte
    final deviceId = AppConfig.deviceId;
    final newEmail = 'dev-$deviceId@streetmedics.local';
    final newPassword = _generatePassword();

    try {
      await client.collection('users').create(body: {
        'email': newEmail,
        'password': newPassword,
        'passwordConfirm': newPassword,
        'name': 'Street Medic',
      });
      await client.collection('users').authWithPassword(newEmail, newPassword);
      await AppConfig.setAuthCredentials(newEmail, newPassword);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Rafraîchit la session si possible (token expiré mais refresh valide).
  /// Retourne true si la session est valide après l'appel.
  static Future<bool> refreshSession() async {
    if (client.authStore.isValid) return true;
    if (client.authStore.token.isEmpty) return false;
    try {
      await client.collection('users').authRefresh();
      return client.authStore.isValid;
    } catch (_) {
      return false;
    }
  }

  /// Force un re-login (utilisé après un 401).
  static Future<bool> forceReLogin() async {
    client.authStore.clear();
    return ensureAuth();
  }

  /// Génère un mot de passe aléatoire (32 octets base64).
  static String _generatePassword() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
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
    return _withAuth(() async {
      final res = await client.collection('reports').create(body: {
        'senderPhone': senderPhone,
        'position': {'lat': lat, 'lng': lng},
        'description': description,
        'status': 'open',
      });
      return res.id;
    });
  }

  /// Liste les SOS **actifs** (ouverts ou pris en charge) avec position,
  /// statut, auteur de la prise en charge et numéro de rappel.
  ///
  /// Les signalements résolus sont exclus : le blip disparaît de la carte.
  static Future<List<Map<String, dynamic>>> listReports() async {
    return _withAuth(() async {
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
    });
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
  /// Met la fiche à `available: false` au lieu de la supprimer : le compte
  /// utilisateur n'a pas toujours la permission DELETE. Pour éviter les
  /// doublons à la reprise de service, on cherche d'abord une fiche
  /// existante via deviceId.
  static Future<void> setMedicOffDuty(String deviceId) async {
    final existing = await _findMedicByDevice(deviceId);
    if (existing != null) {
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

  /// Le patient annule SON SOS (statut → resolved).
  static Future<void> cancelReport(String reportId) async {
    await _withAuth(() async {
      await client.collection('reports').update(reportId, body: {
        'status': 'resolved',
      });
    });
  }

  /// Envoie une entrée de journal (`logs`) au serveur.
  ///
  /// Renvoie `true` si l'entrée a été acceptée, `false` sinon (réseau
  /// indisponible ou règle serveur refusée) : l'appelant conserve alors
  /// l'entrée localement pour un nouvel essai.
  static Future<bool> sendLog(Map<String, dynamic> entry) async {
    try {
      await client.collection('logs').create(body: {
        'deviceId': entry['deviceId'] ?? '',
        'level': entry['level'] ?? 'error',
        'message': entry['message'] ?? '',
        'stack': entry['stack'] ?? '',
        'context': entry['context'] ?? '',
        'appVersion': entry['appVersion'] ?? '',
        'platform': entry['platform'] ?? '',
        'occurredAt': entry['occurredAt'] ?? '',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- Realtime (SSE) ----------

  static final List<UnsubscribeFunc> _unsubscribers = [];
  static UnsubscribeFunc? _connectWatcher;
  static bool _watching = false;
  static bool? _serverReachableCache;
  static bool _realtimeConnected = false;
  static Timer? _fallbackTimer;
  static void Function(bool connected)? onRealtimeStatusChanged;

  /// Vrai si la connexion SSE est active.
  static bool get realtimeConnected => _realtimeConnected;

  /// Abonne la carte aux changements de la collection `reports` (SOS).
  ///
  /// Le SDK PocketBase ne sait pas fermer une connexion SSE qui n'a jamais
  /// abouti : `_sendSubscriptions()` sort tôt tant que `clientId` est vide, et
  /// le client SSE relance indéfiniment (`maxRetry = infinity`) avec des délais
  /// de 200 ms à 2 s. Une seule tentative vers un serveur injoignable crée donc
  /// une boucle de reconnexion éternelle — un timer orphelin qui survit à la
  /// fermeture de l'écran et vide la batterie.
  ///
  /// On ne tente donc la connexion que si le serveur répond.
  static Future<void> subscribeReports(void Function(dynamic) callback) async {
    if (!await _serverReachable()) {
      // Serveur injoignable : pas de SSE, mais la carte doit continuer à se
      // rafraîchir. On lance le polling de secours.
      _startFallbackPolling();
      return;
    }
    _unsubscribers.add(
      await client.realtime.subscribe('reports/*', (e) => callback(e)),
    );
    _watchRealtime();
  }

  /// Abonne la carte aux changements de la collection `medics`.
  static Future<void> subscribeMedics(void Function(dynamic) callback) async {
    if (!await _serverReachable()) {
      _startFallbackPolling();
      return;
    }
    _unsubscribers.add(
      await client.realtime.subscribe('medics/*', (e) => callback(e)),
    );
    _watchRealtime();
  }

  /// Vrai si le serveur répond (et si on ne le sait pas encore, on teste).
  ///
  /// Mis en cache : les deux abonnements de la carte ne déclenchent qu'un seul
  /// `health.check()`. Aucun timer n'est utilisé pour l'invalidation — un
  /// timer orphelin survivrait à la fermeture de l'écran (et fait échouer les
  /// tests : « A Timer is still pending even after the widget tree was
  /// disposed »). C'est `resetServerReachable()` qui invalide le cache,
  /// appelée quand un appel API échoue.
  static Future<bool> _serverReachable() async {
    final cached = _serverReachableCache;
    if (cached != null) return cached;
    final ok = await ping();
    _serverReachableCache = ok;
    return ok;
  }

  /// Invalide le cache de joignabilité : le prochain abonnement retestera.
  ///
  /// À appeler quand un appel API échoue, pour ne pas rester bloqué sur un
  /// « serveur injoignable » alors qu'il est revenu.
  static void resetServerReachable() {
    _serverReachableCache = null;
  }

  /// Notifie la carte de se rafraîchir (utilisé par le fallback polling).
  static final ValueNotifier<int> fallbackRefresh = ValueNotifier<int>(0);

  /// Surveille la connexion SSE : si elle tombe → fallback polling 20s ;
  /// si elle se rétablit → retour au temps réel.
  ///
  /// Idempotent : `subscribeReports` et `subscribeMedics` appellent tous deux
  /// cette méthode. Sans ce garde, le second appel réinstallait un abonnement
  /// `PB_CONNECT` dont la fonction de désabonnement était perdue — la
  /// connexion SSE ne se fermait alors jamais, et sa boucle de reconnexion
  /// continuait de tourner après la fermeture de l'écran (fuite : le test
  /// « Timer is still pending even after the widget tree was disposed »
  /// venait de là, et la batterie se vidait en arrière-plan).
  static void _watchRealtime() {
    if (_watching) return;
    _watching = true;

    client.realtime.onDisconnect = (subs) {
      _setRealtime(false);
    };

    // PB_CONNECT est réémis à chaque reconnexion : on bascule en temps réel.
    // La fonction de désabonnement est CONSERVÉE : sans elle, la connexion
    // SSE ne se ferme pas dans `unsubscribeAll()`.
    client.realtime.subscribe('PB_CONNECT', (e) {
      _setRealtime(true);
    }).then((unsub) {
      _connectWatcher = unsub;
    });
  }

  static void _setRealtime(bool connected) {
    if (_realtimeConnected == connected) return;
    _realtimeConnected = connected;
    onRealtimeStatusChanged?.call(connected);
    if (connected) {
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
    } else {
      _startFallbackPolling();
    }
  }

  /// Polling de secours toutes les 20s si SSE est indisponible.
  static void _startFallbackPolling() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      fallbackRefresh.value++;
    });
  }

  /// Désabonne toutes les subscriptions réaltime et arrête le fallback.
  ///
  /// Ferme aussi l'abonnement `PB_CONNECT` et réinitialise l'état : sans cela
  /// la connexion SSE survit à la fermeture de l'écran et sa boucle de
  /// reconnexion continue de tourner (timer orphelin + batterie).
  static Future<void> unsubscribeAll() async {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    // Ferme l'abonnement PB_CONNECT (celui qui maintient la connexion ouverte).
    try {
      await _connectWatcher?.call();
    } catch (_) {
      // Déjà fermé / connexion perdue : rien à faire.
    }
    _connectWatcher = null;
    _watching = false;

    for (final unsub in _unsubscribers) {
      try {
        await unsub();
      } catch (_) {
        // Idem : ne pas bloquer le nettoyage sur un désabonnement déjà mort.
      }
    }
    _unsubscribers.clear();

    // NE PAS appeler `client.realtime.unsubscribe()` ici : chaque appel passe
    // par `_submitSubscriptions()`, qui programme un micro-timer même quand
    // plus aucun abonnement ne reste (observé en test : « A Timer is still
    // pending even after the widget tree was disposed »). Les fonctions de
    // désabonnement individuelles ci-dessus suffisent : elles retirent les
    // écouteurs et, une fois la liste vide, le SDK ferme la connexion SSE.

    _realtimeConnected = false;
  }

  /// Liste les medics EN SERVICE, avec position.
  ///
  /// Seuls les medics `available = true` sont renvoyés : une fiche laissée
  /// par une fin de service (ou par une ancienne installation) ne doit
  /// jamais apparaître comme un blip sur la carte.
  static Future<List<Map<String, dynamic>>> listMedics() async {
    final res = await client
        .collection('medics')
        .getList(perPage: 200, filter: 'available = true');
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