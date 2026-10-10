// Test de fumée : l'app démarre et affiche l'onglet SOS (localisé).
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/phone_utils.dart';
import 'package:street_medics_app/main.dart';

void main() {
  testWidgets('L\'app démarre et affiche l\'onglet SOS',
      (WidgetTester tester) async {
    await tester.pumpWidget(const StreetMedicsApp());
    await tester.pump(const Duration(milliseconds: 100));
    // En test, la locale par défaut est l'anglais.
    expect(find.text('Need help?'), findsOneWidget);
    expect(find.text('SEND MY POSITION'), findsOneWidget);
  });

  group('normalizePhone', () {
    test('Double préfixe 33+336... → +336...', () {
      expect(normalizePhone('33+3361234567'), '+3361234567');
    });

    test('Double préfixe +33+336... → +336...', () {
      expect(normalizePhone('+33+3361234567'), '+3361234567');
    });

    test('Préfixe simple +336... inchangé', () {
      expect(normalizePhone('+3361234567'), '+3361234567');
    });

    test('Numéro local 06... → +336...', () {
      expect(normalizePhone('0612345678'), '+33612345678');
    });

    test('Numéro avec espaces et tirets', () {
      expect(normalizePhone('06 12 34 56 78'), '+33612345678');
    });

    test('Numéro déjà correct reste inchangé', () {
      expect(normalizePhone('+33712345678'), '+33712345678');
    });
  });
}
