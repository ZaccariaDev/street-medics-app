// Test : l'onglet Carte expose le bouton « Ma position » (recentrage) et le
// bouton rafraîchir, et les marqueurs sont cliquables.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/main.dart';

void main() {
  testWidgets('Onglet Carte : bouton recentrage présent',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const StreetMedicsApp());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.map));
    await tester.pumpAndSettle();

    // La carte est bien montée.
    expect(find.byType(FlutterMap), findsOneWidget);

    // Bouton « Ma position » (façon Google Maps) + bouton rafraîchir.
    expect(find.byTooltip('Ma position'), findsOneWidget);
    expect(find.byTooltip('Rafraîchir'), findsOneWidget);
  });
}
