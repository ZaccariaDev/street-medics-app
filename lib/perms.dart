import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import 'l10n/app_localizations.dart';
import 'notifs.dart';

/// Demande et vérifie les permissions nécessaires à l'app.
///
/// Trois niveaux :
///  - notifications (Android 13+) : pour l'alerte de proximité ;
///  - localisation « pendant l'utilisation » : pour envoyer un SOS ;
///  - localisation « toujours » (arrière-plan) + exemption d'optimisation de
///    batterie : pour que le suivi continue quand le medic ferme l'app.
class Perms {
  /// Notifications (Android 13+).
  ///
  /// La demande est sérialisée dans Notifs.requestPermissions() : deux
  /// demandes concurrentes font planter Android
  /// (permissionRequestInProgress).
  static Future<bool> notifications() async {
    await Notifs.requestPermissions();
    return true;
  }

  /// Localisation « pendant l'utilisation ».
  static Future<bool> locationForeground() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return p == LocationPermission.whileInUse ||
        p == LocationPermission.always;
  }

  /// Localisation « toujours » (arrière-plan).
  ///
  /// Sur Android 11+, le Foreground Service (type location) prend le relais
  /// sans exiger le réglage « Toujours autoriser » du système : la permission
  /// normale (whileInUse) suffit pour que la position continue quand l'app
  /// est minimisée ou l'écran verrouillé. Google Play refuse
  /// ACCESS_BACKGROUND_LOCATION sans formulaire + vidéo ; on s'en passe.
  static Future<bool> locationBackground({bool openSettings = true}) async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  /// Exemption d'optimisation de batterie (le service survit mieux).
  ///
  /// Android 12+ peut ne pas afficher la boîte de dialogue : on bascule alors
  /// vers l'écran de réglages correspondant.
  static Future<void> batteryOptimization() async {
    if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) return;
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {
      await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    }
    // Repli : si toujours pas exempté, ouvrir l'écran de réglages.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    }
  }

  /// Enchaîne toutes les demandes (1er lancement).
  static Future<void> requestAll() async {
    await notifications();
    final ok = await locationForeground();
    if (ok) await locationBackground();
    await batteryOptimization();
  }

  /// Vérifie que tout est prêt pour prendre le service.
  /// Renvoie les clés de traduction des éléments manquants.
  static Future<List<String>> missingForDuty() async {
    final missing = <String>[];
    if (!await notifications()) missing.add('permNotif');
    if (!await locationForeground()) missing.add('permLoc');
    if (!await locationBackground(openSettings: false)) missing.add('permBack');
    return missing;
  }

  /// Libellé traduit d'une clé de permission manquante.
  static String label(AppLocalizations t, String key) {
    switch (key) {
      case 'permNotif':
        return t.permNotif;
      case 'permLoc':
        return t.permLoc;
      case 'permBack':
        return t.permBack;
      default:
        return key;
    }
  }

  /// Boîte de dialogue listant ce qui est demandé / ce qui manque.
  ///
  /// [duty] = true quand elle est affichée à la prise de service.
  static Future<void> askDialog(
    BuildContext context, {
    bool duty = false,
    List<String> missing = const [],
  }) async {
    final t = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.shield, color: Colors.red),
        title: Text(t.permTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(duty ? t.permDutyBody : t.permBody),
            const SizedBox(height: 12),
            if (missing.isEmpty) ...[
              _line(Icons.notifications_active, t.permNotif),
              _line(Icons.location_on, t.permLoc),
              _line(Icons.sync, t.permBack),
              _line(Icons.battery_saver, t.permBattery),
            ] else
              for (final m in missing) _line(Icons.error_outline, label(t, m)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.later),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              requestAll();
            },
            child: Text(t.allow),
          ),
        ],
      ),
    );
  }

  static Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
