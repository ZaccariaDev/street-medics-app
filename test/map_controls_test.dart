// Test : l'onglet Carte expose le bouton « Ma position » (recentrage) et le
// bouton rafraîchir. La carte n'est visible que pour un medic en service.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:street_medics_app/config.dart';
import 'package:street_medics_app/main.dart';

/// Sélectionne un onglet via le callback de la barre de navigation.
/// (Plus fiable en test que `tap()`, la barre pouvant être obscurcie.)
Future<void> selectTab(WidgetTester tester, int index) async {
  final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
  nav.onDestinationSelected!(index);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Onglet Carte : bouton recentrage présent',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'flutter.on_duty': true});
    await AppConfig.load();

    await tester.pumpWidget(const StreetMedicsApp());
    await tester.pump(const Duration(milliseconds: 100));

    await selectTab(tester, 1);

    expect(find.byType(FlutterMap), findsOneWidget);
    // Locale de test = anglais.
    expect(find.byTooltip('My position'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
  });

  testWidgets('Onglet Plan verrouillé pour un non-medic',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'flutter.on_duty': false});
    await AppConfig.load();

    await tester.pumpWidget(const StreetMedicsApp());
    await tester.pump(const Duration(milliseconds: 100));

    // L'onglet est grisé : l'icône cadenas remplace l'icône carte.
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.map), findsNothing);

    // Tenter d'ouvrir l'onglet verrouillé ne montre pas la carte.
    await selectTab(tester, 1);
    expect(find.byType(FlutterMap), findsNothing);
  });
}
