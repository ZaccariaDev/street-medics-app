// Test : l'onglet Carte expose le bouton « Ma position » (recentrage) et le
// bouton rafraîchir. La carte n'est visible que pour un medic EN SERVICE et
// CONNECTÉ (la lecture des signalements exige un compte).
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:street_medics_app/config.dart';
import 'package:street_medics_app/main.dart';
import 'package:street_medics_app/pb_service.dart';

/// Sélectionne un onglet via le callback de la barre de navigation.
/// (Plus fiable en test que `tap()`, la barre pouvant être obscurcie.)
Future<void> selectTab(WidgetTester tester, int index) async {
  final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
  nav.onDestinationSelected!(index);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Onglet Carte : bouton recentrage présent (medic connecté)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'flutter.on_duty': true});
    await AppConfig.load();
    // Jeton JWT factice mais bien formé (isValid vérifie l'expiration).
    PbService.client.authStore.save(
      'eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJleHAiOiAxNzkxNjU5Mzg1LCAiaWQiOiAidTEiLCAiY29sbGVjdGlvbklkIjogInVzZXJzIiwgInR5cGUiOiAiYXV0aCJ9.sig',
      RecordModel.fromJson({
        'id': 'u1',
        'collectionId': 'users',
        'collectionName': 'users',
        'email': 'medic@test.local',
      }),
    );

    await tester.pumpWidget(const StreetMedicsApp());
    await tester.pump(const Duration(milliseconds: 100));

    await selectTab(tester, 1);

    expect(find.byType(FlutterMap), findsOneWidget);
    // Locale de test = anglais.
    expect(find.byTooltip('My position'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
  });

  testWidgets('Onglet Plan verrouillé sans compte', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'flutter.on_duty': true});
    await AppConfig.load();
    PbService.client.authStore.clear(); // pas connecté

    await tester.pumpWidget(const StreetMedicsApp());
    await tester.pump(const Duration(milliseconds: 100));

    // L'onglet est grisé : cadenas au lieu de l'icône carte.
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.map), findsNothing);

    await selectTab(tester, 1);
    expect(find.byType(FlutterMap), findsNothing);
  });

  testWidgets('Onglet Plan verrouillé hors service (même connecté)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'flutter.on_duty': false});
    await AppConfig.load();
    // Jeton JWT factice mais bien formé (isValid vérifie l'expiration).
    PbService.client.authStore.save(
      'eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJleHAiOiAxNzkxNjU5Mzg1LCAiaWQiOiAidTEiLCAiY29sbGVjdGlvbklkIjogInVzZXJzIiwgInR5cGUiOiAiYXV0aCJ9.sig',
      RecordModel.fromJson({
        'id': 'u1',
        'collectionId': 'users',
        'collectionName': 'users',
        'email': 'medic@test.local',
      }),
    );

    await tester.pumpWidget(const StreetMedicsApp());
    await tester.pump(const Duration(milliseconds: 100));

    await selectTab(tester, 1);
    expect(find.byType(FlutterMap), findsNothing);
  });
}
