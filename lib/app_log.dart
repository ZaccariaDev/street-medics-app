import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'config.dart';
import 'pb_service.dart';

/// Journalisation des erreurs et avertissements de l'application.
///
/// Objectif : pouvoir diagnostiquer à distance un bug survenu sur l'appareil
/// d'un utilisateur sans lui demander de brancher un câble USB.
///
/// Fonctionnement :
///  1. **Capture** — les erreurs non gérées (`FlutterError.onError`), les
///     erreurs asynchrones (`PlatformDispatcher.instance.onError`) et les
///     avertissements (`debugPrint`) sont interceptés.
///  2. **Persistance locale** — chaque entrée est écrite dans un fichier
///     (`logs.jsonl`) dans le dossier de l'app, une ligne JSON par entrée.
///     Ce fichier survit à la fermeture de l'app : il contient donc les
///     traces de l'exécution **précédente**.
///  3. **Envoi** — au démarrage (et périodiquement), les entrées non encore
///     transmises sont envoyées à la collection `logs` du serveur, puis
///     supprimées du fichier local en cas de succès.
///
/// Le fichier reste volontairement petit : on plafonne le nombre d'entrées
/// conservées pour ne jamais faire grossir le stockage de l'utilisateur.
class AppLog {
  AppLog._();

  /// Nombre maximal d'entrées conservées localement (les plus récentes).
  static const int _maxEntries = 300;

  /// Taille maximale d'un message envoyé (le serveur plafonne à 4000).
  static const int _maxMessageLen = 4000;

  static File? _file;
  static final List<Map<String, dynamic>> _buffer = [];
  static bool _sending = false;
  static Timer? _flushTimer;

  /// Installe les gestionnaires d'erreurs globaux et charge les traces
  /// laissées par l'exécution précédente. À appeler au tout début de `main`.
  static Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/logs.jsonl');
      if (!await _file!.exists()) {
        await _file!.create(recursive: true);
      }
      await _loadFromDisk();
    } catch (_) {
      // Pas de stockage disponible : on journalise en mémoire seulement.
      _file = null;
    }

    // Erreurs de build / rendu Flutter.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      log(
        level: 'error',
        message: details.exceptionAsString(),
        stack: details.stack?.toString() ?? '',
        context: details.library ?? 'flutter',
      );
    };

    // Erreurs asynchrones hors du cycle Flutter.
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      log(
        level: 'error',
        message: error.toString(),
        stack: stack.toString(),
        context: 'async',
      );
      return true; // on a traité l'erreur
    };

    // Avertissements : on intercepte `debugPrint` pour capter les messages
    // de diagnostic (warnings Dart, avertissements de packages...).
    // Seuls les messages contenant un mot-clé d'alerte sont conservés, pour
    // ne pas remplir le stockage avec des traces de debug ordinaires.
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      originalDebugPrint(message, wrapWidth: wrapWidth);
      if (message == null) return;
      final lower = message.toLowerCase();
      if (lower.contains('error') ||
          lower.contains('warning') ||
          lower.contains('exception') ||
          lower.contains('failed') ||
          lower.contains('erreur') ||
          lower.contains('échec')) {
        log(level: 'warning', message: message, context: 'debugPrint');
      }
    };

    // Envoi périodique (toutes les 60 s) tant que l'app tourne.
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 60), (_) => flush());
  }

  /// Journalise une entrée. `level` : "error", "warning" ou "info".
  static void log({
    required String level,
    required String message,
    String stack = '',
    String context = '',
  }) {
    final entry = <String, dynamic>{
      'level': level,
      'message': _truncate(message, _maxMessageLen),
      'stack': _truncate(stack, 8000),
      'context': _truncate(context, 2000),
      'deviceId': AppConfig.deviceId,
      'appVersion': AppConfig.appVersion,
      'platform': Platform.isAndroid ? 'android' : 'ios',
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
    };
    _buffer.add(entry);
    // On garde les entrées les plus récentes.
    while (_buffer.length > _maxEntries) {
      _buffer.removeAt(0);
    }
    _appendToDisk(entry);
  }

  /// Envoie au serveur les entrées non encore transmises.
  ///
  /// Les entrées envoyées avec succès sont retirées du stockage local.
  /// En cas d'échec réseau, elles restent et seront renvoyées plus tard.
  static Future<void> flush() async {
    if (_sending || _buffer.isEmpty) return;
    _sending = true;
    try {
      final pending = List<Map<String, dynamic>>.from(_buffer);
      for (final entry in pending) {
        final ok = await PbService.sendLog(entry);
        if (!ok) break; // réseau indisponible : on réessaiera
        _buffer.remove(entry);
      }
      await _rewriteDisk();
    } catch (_) {
      // Silencieux : nouvel essai au prochain cycle.
    } finally {
      _sending = false;
    }
  }

  // ---------- persistance ----------

  static Future<void> _loadFromDisk() async {
    try {
      final content = await _file!.readAsString();
      for (final line in content.split('\n')) {
        if (line.trim().isEmpty) continue;
        try {
          final m = jsonDecode(line);
          if (m is Map<String, dynamic>) _buffer.add(m);
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<void> _appendToDisk(Map<String, dynamic> entry) async {
    try {
      await _file?.writeAsString(
        '${jsonEncode(entry)}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  static Future<void> _rewriteDisk() async {
    try {
      final content =
          _buffer.map((e) => jsonEncode(e)).join('\n');
      await _file?.writeAsString(content.isEmpty ? '' : '$content\n');
    } catch (_) {}
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
