import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Tâche d'arrière-plan : tant que le medic est en service, elle
///  1. met à jour sa position côté serveur toutes les 30 s ;
///  2. interroge les SOS et déclenche une notification + un son distinctif
///     dès qu'un signalement apparaît dans le rayon d'alerte du medic.
///
/// Elle tourne dans un isolate séparé : elle survit à la fermeture de l'app.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MedicTaskHandler());
}

class MedicTaskHandler extends TaskHandler {
  Timer? _timer;
  http.Client? _client;
  final _notifs = FlutterLocalNotificationsPlugin();
  bool _notifsReady = false;

  String _base = '';
  String _deviceId = '';
  double _radiusKm = 2.0;

  /// SOS déjà signalés (évite de re-notifier en boucle).
  final Set<String> _alerted = {};

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _client = http.Client();
    await _loadConfig();
    await _initNotifs();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _cycle());
    await _cycle();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _cycle();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _timer?.cancel();
    _client?.close();
  }

  Future<void> _loadConfig() async {
    final p = await FlutterForegroundTask.getData<String>(key: 'cfg');
    if (p != null && p.isNotEmpty) {
      try {
        final m = jsonDecode(p) as Map<String, dynamic>;
        _base = (m['base'] ?? '').toString();
        _deviceId = (m['deviceId'] ?? '').toString();
        _radiusKm = (m['radiusKm'] as num?)?.toDouble() ?? 2.0;
      } catch (_) {}
    }
  }

  Future<void> _initNotifs() async {
    try {
      await _notifs.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _notifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
        'sos_alerts',
        'SOS alerts',
        description: 'Alertes de proximité des signalements SOS',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('alarm'),
        enableVibration: true,
      ));
      _notifsReady = true;
    } catch (_) {
      _notifsReady = false;
    }
  }

  Future<void> _cycle() async {
    try {
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          );

      if (_deviceId.isNotEmpty && _base.isNotEmpty) {
        await _client!.patch(
          Uri.parse('$_base/api/collections/medics/records/$_deviceId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'position': {'lat': pos.latitude, 'lng': pos.longitude},
            // La règle de mise à jour du serveur exige le deviceId.
            'deviceId': _deviceId,
          }),
        );
      }

      await _checkAlerts(pos);
    } catch (_) {
      // Silencieux : on retentera au prochain cycle.
    }
  }

  Future<void> _checkAlerts(Position me) async {
    if (_base.isEmpty) return;
    final res = await _client!.get(
      Uri.parse('$_base/api/collections/reports/records'
          '?perPage=100&filter=${Uri.encodeComponent('status="open"')}'),
    );
    if (res.statusCode != 200) return;

    final items = (jsonDecode(res.body)['items'] as List?) ?? [];
    for (final it in items) {
      final pos = it['position'];
      if (pos is! Map) continue;
      final lat = (pos['lat'] as num?)?.toDouble();
      final lng = (pos['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final id = it['id'].toString();
      if (_alerted.contains(id)) continue;

      final dKm = _distanceKm(me.latitude, me.longitude, lat, lng);
      if (dKm <= _radiusKm) {
        _alerted.add(id);
        await _alert(it, dKm);
      }
    }
  }

  Future<void> _alert(Map<dynamic, dynamic> it, double dKm) async {
    final dist = dKm < 1
        ? '${(dKm * 1000).round()} m'
        : '${dKm.toStringAsFixed(1)} km';
    final desc = (it['description'] ?? '').toString();

    // Notifie l'UI si l'app est ouverte.
    FlutterForegroundTask.sendDataToMain({
      'type': 'sos_alert',
      'id': it['id'].toString(),
      'lat': it['position']['lat'],
      'lng': it['position']['lng'],
      'distanceKm': dKm,
      'description': desc,
    });

    // Notification système avec le son distinctif (fonctionne app fermée).
    if (_notifsReady) {
      await _notifs.show(
        id: 42,
        title: 'SOS • $dist',
        body: desc.isEmpty ? 'Signalement proche' : desc,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'sos_alerts',
            'SOS alerts',
            channelDescription: 'Alertes de proximité des signalements SOS',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('alarm'),
            enableVibration: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
          ),
        ),
        payload: jsonEncode({'type': 'sos_alert', 'lat': it['position']['lat'], 'lng': it['position']['lng']}),
      );
    }

    await FlutterForegroundTask.updateService(
      notificationTitle: 'SOS • $dist',
      notificationText: desc.isEmpty ? 'Signalement proche' : desc,
    );
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double d) => d * math.pi / 180.0;
}
