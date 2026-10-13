import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'emergency_numbers.dart';

/// Notifications locales : alerte de proximité d'un SOS (son distinctif)
/// et bandeau du service d'arrière-plan.
class Notifs {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static const _alertChannel = 'sos_alerts';
  static const _serviceChannel = 'foreground_service';

  /// Init paresseuse (appelée au démarrage et depuis le service).
  static Future<void> init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onTap,
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      _alertChannel,
      'SOS alerts',
      description: 'Alertes de proximité des signalements SOS',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarm'),
      enableVibration: true,
    ));
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      _serviceChannel,
      'Foreground service',
      description: 'Suivi de position en arrière-plan',
      importance: Importance.low,
    ));
    _inited = true;
  }

  static bool _requesting = false;

  /// Demande la permission de notification (Android 13+).
  ///
  /// Sur Android, `requestNotificationsPermission()` ne peut pas être appelé
  /// en parallèle : une deuxième demande lève `permissionRequestInProgress`.
  /// On sérialise avec un mutex pour éviter ce crash.
  static Future<void> requestPermissions() async {
    if (_requesting) return;
    _requesting = true;
    try {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await impl?.requestNotificationsPermission();
    } catch (_) {
      // Permission refusée ou déjà demandée : pas grave.
    } finally {
      _requesting = false;
    }
  }

  /// Affiche l'alerte de proximité avec le son distinctif.
  static Future<void> showSosAlert({
    required String title,
    required String body,
    double? lat,
    double? lng,
  }) async {
    await init();
    const details = AndroidNotificationDetails(
      _alertChannel,
      'SOS alerts',
      channelDescription: 'Alertes de proximité des signalements SOS',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarm'),
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );
    await _plugin.show(
      id: 42,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: details,
        iOS: DarwinNotificationDetails(
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: jsonEncode({'type': 'sos_alert', 'lat': lat, 'lng': lng}),
    );
  }

  /// Bandeau persistant du service d'arrière-plan (avec bouton fin de service).
  static Future<void> showService({
    required String title,
    required String body,
  }) async {
    await init();
    const details = AndroidNotificationDetails(
      _serviceChannel,
      'Foreground service',
      channelDescription: 'Suivi de position en arrière-plan',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      showWhen: false,
    );
    await _plugin.show(
      id: 101,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: details),
    );
  }

  static void _onTap(NotificationResponse r) {
    // Le tap ouvre simplement l'app (comportement par défaut).
  }
}

/// Langue de l'app : par défaut celle du téléphone, surchargeable.
class Lang {
  static const supported = [
    'en', 'fr', 'ar', 'bn', 'de', 'el', 'es', 'fa', 'he', 'hi', 'id', 'it',
    'ja', 'ko', 'nl', 'pl', 'pt', 'ro', 'ru', 'sw', 'tr', 'uk', 'vi', 'zh',
  ];

  static const _names = {
    'en': 'English', 'fr': 'Français', 'ar': 'العربية', 'bn': 'বাংলা',
    'de': 'Deutsch', 'el': 'Ελληνικά', 'es': 'Español', 'fa': 'فارسی',
    'he': 'עברית', 'hi': 'हिन्दी', 'id': 'Indonesia', 'it': 'Italiano',
    'ja': '日本語', 'ko': '한국어', 'nl': 'Nederlands', 'pl': 'Polski',
    'pt': 'Português', 'ro': 'Română', 'ru': 'Русский', 'sw': 'Kiswahili',
    'tr': 'Türkçe', 'uk': 'Українська', 'vi': 'Tiếng Việt', 'zh': '中文',
  };

  static String name(String code) => _names[code] ?? code;

  /// Résout la locale à utiliser : surcharge utilisateur, sinon langue du
  /// téléphone, sinon anglais.
  static Locale resolve(String? override) {
    if (override != null && override.isNotEmpty) return Locale(override);
    final sys = PlatformDispatcher.instance.locale;
    final code = sys.languageCode;
    if (supported.contains(code)) return Locale(code);
    return const Locale('en');
  }
}

/// Numéros d'urgence du pays courant.
class Emergency {
  /// Renvoie la liste (numéro, services) pour un code pays donné, triée :
  /// les numéros généraux (tous services) d'abord, puis ambulance, police,
  /// pompiers, puis les autres. Toujours au moins le 112 en secours.
  static List<MapEntry<String, List<String>>> numbersFor(String? countryCode) {
    final code = (countryCode ?? '').toUpperCase();
    final raw = emergencyNumbers[code] ?? const [];
    final out = <MapEntry<String, List<String>>>[];

    int rank(List<String> t) {
      if (t.length >= 3) return 0; // tous services (ex: 112, 911)
      if (t.contains('ambulance')) return 1;
      if (t.contains('police')) return 2;
      if (t.contains('fire')) return 3;
      if (t.isEmpty) return 5; // lignes spécialisées (info, etc.)
      return 4;
    }

    final list = raw
        .map((e) => MapEntry(
            e['n'].toString(), (e['t'] as List).cast<String>()))
        .toList()
      ..sort((a, b) => rank(a.value).compareTo(rank(b.value)));

    out.addAll(list);
    if (!out.any((e) => e.key == '112')) {
      out.add(const MapEntry('112', <String>['police', 'ambulance', 'fire']));
    }
    return out;
  }
}
