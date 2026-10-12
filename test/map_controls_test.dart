// Test : l'onglet Carte expose le bouton « Ma position » (recentrage) et le
// bouton rafraîchir. La carte n'est visible que pour un medic EN SERVICE :
// envoyer un SOS rend automatiquement hors service (on est victime).
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:street_medics_app/config.dart';
import 'package:street_medics_app/main.dart';

/// Sélectionne un onglet via le callback de la barre de navigation.
/// (Plus fiable en test que `tap()`, la barre pouvant être obscurcie.)
///
/// On utilise `pump()` et non `pumpAndSettle()` : la carte arme un
/// `Timer.periodic` de rafraîchissement qui ne s'arrête jamais, or
/// `pumpAndSettle()` attend qu'AUCUN timer ne soit actif — il boucle donc
/// indéfiniment et le test n'aboutit pas. `pump()` avance d'une frame, ce qui
/// suffit à construire l'onglet.
Future<void> selectTab(WidgetTester tester, int index) async {
  final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
  nav.onDestinationSelected!(index);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('Onglet Carte : bouton recentrage présent (medic en service)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // `device_id` est OBLIGATOIRE ici : sans lui, `AppConfig.load()` appelle
    // `DeviceInfoPlugin().androidInfo`, un canal de plateforme natif qui ne
    // répond jamais en test — le test se fige indéfiniment.
    SharedPreferences.setMockInitialValues({
      'flutter.on_duty': true,
      'device_id': 'dev-test',
    });
    await AppConfig.load();

    await tester.pumpWidget(const StreetMedicsApp());
    await tester.pump(const Duration(milliseconds: 100));

    await selectTab(tester, 1);

    expect(find.byType(FlutterMap), findsOneWidget);
    // Locale de test = anglais.
    expect(find.byTooltip('My position'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
  });

  testWidgets('Onglet Plan verrouillé hors service', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'flutter.on_duty': false,
      'device_id': 'dev-test',
    });
    await AppConfig.load();

    await tester.pumpWidget(const StreetMedicsApp());
    await tester.pump(const Duration(milliseconds: 100));

    // L'onglet est grisé : cadenas au lieu de l'icône carte.
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.map), findsNothing);

    await selectTab(tester, 1);
    expect(find.byType(FlutterMap), findsNothing);
  });
}
