// Test : la carte ne peut pas dézoomer au-delà de la taille de l'interface.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:street_medics_app/config.dart';
import 'package:street_medics_app/main.dart';

void main() {
  testWidgets('La carte borne le dézoom (pas de dézoom infini)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // L'onglet Plan n'est accessible qu'aux medics EN SERVICE.
    SharedPreferences.setMockInitialValues({'flutter.on_duty': true});
    await AppConfig.load();

    await tester.pumpWidget(const StreetMedicsApp());
    await tester.pump(const Duration(milliseconds: 100));

    // Aller sur l'onglet Carte via la barre de navigation.
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    nav.onDestinationSelected!(1);
    await tester.pumpAndSettle();

    final mapState = tester.state(find.byType(FlutterMap));
    final map = mapState.widget as FlutterMap;
    final constraint = map.options.cameraConstraint;

    // Interface disponible (comme en vrai) : 1080/3 x 2400/3.
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;

    MapCamera cameraAt(double zoom) => MapCamera(
          crs: const Epsg3857(),
          center: const LatLng(46.6, 2.4),
          zoom: zoom,
          rotation: 0,
          nonRotatedSize: size,
        );

    // Dézoomé à fond : le monde ne peut pas rester dans l'interface.
    // La contrainte doit REJETER ce mouvement (null) — le contrôleur bloque
    // alors le geste, donc impossible de dézoomer à l'infini.
    expect(
      constraint.constrain(cameraAt(0)),
      isNull,
      reason: 'Dézoomé trop loin, la carte doit bloquer le geste',
    );

    // Zoom normal : la contrainte accepte le mouvement.
    final ok = constraint.constrain(cameraAt(6));
    expect(ok, isNotNull, reason: 'Un zoom normal doit rester possible');
    expect(ok!.center.latitude, inInclusiveRange(-85, 85));
    expect(ok.center.longitude, inInclusiveRange(-180, 180));
  });
}
