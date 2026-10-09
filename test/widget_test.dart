// Test de fumée : l'app démarre et affiche l'onglet SOS.
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/main.dart';

void main() {
  testWidgets('L\'app démarre et affiche l\'onglet SOS',
      (WidgetTester tester) async {
    await tester.pumpWidget(const StreetMedicsApp());
    expect(find.text('Besoin d\'aide ?'), findsOneWidget);
    expect(find.text('ENVOYER MA POSITION'), findsOneWidget);
  });
}
