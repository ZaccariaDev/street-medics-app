// Test de fumée : l'app démarre et affiche l'onglet SOS (localisé).
import 'package:flutter_test/flutter_test.dart';

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
}
