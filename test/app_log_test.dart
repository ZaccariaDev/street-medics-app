// Test du filtrage des erreurs réseau dans AppLog.
//
// Objectif : prouver que les erreurs réseau passagères (SocketException,
// échec DNS, timeout) ne remontent PAS au canal Discord. Ce sont des
// événements normaux (déconnexion, coupure mobile), pas des bugs.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:street_medics_app/app_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Mocker le canal path_provider pour getApplicationSupportDirectory
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      },
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLog.init();
    // Vider le fichier de logs pour que chaque test repart propre.
    // Sans cela, une entrée écrite par un test précédent fausse les
    // assertions des tests suivants (logs.jsonl persiste entre les tests
    // car le dossier temporaire n'est pas recréé).
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/logs.jsonl');
    if (await f.exists()) await f.delete();
  });

  /// Lit les entrées du fichier de logs de l'app.
  Future<List<Map<String, dynamic>>> readLogs() async {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/logs.jsonl');
    if (!f.existsSync()) return [];
    final lines = f.readAsStringSync().split('\n');
    return lines
        .where((l) => l.trim().isNotEmpty)
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
  }

  group('filtrage réseau', () {
    test('SocketException n\'est pas journalisée', () async {
      const message =
          'ClientException with SocketException: '
          'Failed host lookup: \'api.xpertise.quest\' (OS Error: '
          'No address associated with hostname, errno = 7)';
      AppLog.log(level: 'error', message: message, context: 'test');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(await readLogs(), isEmpty,
          reason: 'une erreur réseau ne doit pas être journalisée');
    });

    test('TimeoutException n\'est pas journalisée', () async {
      const message =
          'ClientException: Connection TimeoutException: '
          'Connection timeout';
      AppLog.log(level: 'error', message: message, context: 'test');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(await readLogs(), isEmpty,
          reason: 'un timeout réseau ne doit pas être journalisé');
    });

    test('les erreurs HTTP 504 ne sont pas journalisées', () async {
      const msg = 'ClientException: {url: https://api.xpertise.quest, statusCode: 504}';
      AppLog.log(level: 'error', message: msg, context: 'test');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(await readLogs(), isEmpty);
    });

    test('les erreurs de décodage image ne sont pas journalisées', () async {
      const msg = 'Exception: Invalid image data';
      AppLog.log(level: 'error', message: msg, context: 'test');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(await readLogs(), isEmpty);
    });

    test('une vraie erreur est bien journalisée', () async {
      const message = 'ArgumentError: Invalid argument: null';
      AppLog.log(level: 'error', message: message, context: 'test');
      await Future.delayed(const Duration(milliseconds: 100));
      final logs = await readLogs();
      expect(logs, isNotEmpty,
          reason: 'une vraie erreur doit être journalisée');
      expect(logs.first['message'], contains('ArgumentError'));
    });
  });
}
