// Tests du multisignalement : un appareil peut envoyer PLUSIEURS SOS.
//
// Cas d'usage réel : en manifestation, un témoin voit 3 blessés et envoie
// 3 SOS, chacun avec sa description. Le premier SOS doit rester un simple
// appui (aucun clic supplémentaire par rapport à avant).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:street_medics_app/config.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'device_id': 'dev-test',
      'flutter.on_duty': false,
    });
  });

  group('multisignalement', () {
    test('un SOS : la liste contient un seul id', () async {
      await AppConfig.load();
      await AppConfig.addMyReport('r1');
      expect(AppConfig.myReports, ['r1']);
      expect(AppConfig.myReportId, 'r1');
      expect(AppConfig.hasMyReports, isTrue);
    });

    test('trois SOS : les trois sont conservés dans l\'ordre', () async {
      await AppConfig.load();
      await AppConfig.addMyReport('r1');
      await AppConfig.addMyReport('r2');
      await AppConfig.addMyReport('r3');
      expect(AppConfig.myReports, ['r1', 'r2', 'r3']);
      expect(AppConfig.hasMyReports, isTrue);
    });

    test('annuler le dernier retire uniquement celui-là', () async {
      await AppConfig.load();
      await AppConfig.addMyReport('r1');
      await AppConfig.addMyReport('r2');
      await AppConfig.removeMyReport('r2');
      expect(AppConfig.myReports, ['r1']);
      expect(AppConfig.myReportId, 'r1');
    });

    test('le même id n\'est jamais ajouté deux fois', () async {
      await AppConfig.load();
      await AppConfig.addMyReport('r1');
      await AppConfig.addMyReport('r1');
      expect(AppConfig.myReports, ['r1']);
    });

    test('après annulation du dernier SOS, la liste est vide', () async {
      await AppConfig.load();
      await AppConfig.addMyReport('r1');
      await AppConfig.removeMyReport('r1');
      expect(AppConfig.myReports, isEmpty);
      expect(AppConfig.hasMyReports, isFalse);
      expect(AppConfig.myReportId, '');
    });

    test('la liste survit à un redémarrage (persistance)', () async {
      await AppConfig.load();
      await AppConfig.addMyReport('r1');
      await AppConfig.addMyReport('r2');
      // Simule un redémarrage : on relit la config depuis les préférences.
      await AppConfig.load();
      expect(AppConfig.myReports, ['r1', 'r2']);
    });

    test('reprise de l\'ancien format : my_report_id migre vers la liste',
        () async {
      SharedPreferences.setMockInitialValues({
        'device_id': 'dev-test',
        'my_report_id': 'ancien-sos',
      });
      await AppConfig.load();
      expect(AppConfig.myReports, ['ancien-sos']);
      expect(AppConfig.myReportId, 'ancien-sos');
    });
  });
}
