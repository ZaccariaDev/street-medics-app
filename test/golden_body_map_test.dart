// Preuve visuelle : rendu REEL du widget par le moteur Flutter.
//
// Genere des images du selecteur de blessures tel que Flutter le peint
// vraiment (SVG inclus), sans passer par le telephone.
//
// Usage : flutter test test/golden_body_map_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';
import 'package:street_medics_app/body_map_view.dart';

void main() {
  testWidgets('rendu des deux vues', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    for (final v in BodyView.values) {
      final injuries = v == BodyView.front
          ? const [
              Injury(zoneId: 'head', typeId: 'wound'),
              Injury(zoneId: 'chest', typeId: 'fracture'),
              Injury(zoneId: 'shin_l', typeId: 'burn'),
            ]
          : const [
              Injury(zoneId: 'back', typeId: 'wound'),
              Injury(zoneId: 'arm_r', typeId: 'fracture'),
            ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('shot'),
              child: Container(
                width: 300,
                height: 620,
                color: Colors.white,
                child: BodyMapView(
                  view: v,
                  injuries: injuries,
                  zoomEnabled: false,
                  onZoneTapped: (_) {},
                ),
              ),
            ),
          ),
        ),
      ));
      // Charge le SVG (E/S reelles) puis laisse le moteur peindre.
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('shot')));
      // toImage/toByteData doivent tourner dans runAsync : sinon le Future
      // reel ne se resout jamais et le test pend indefiniment.
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final out = File('/tmp/render_${v.name}.png');
        out.writeAsBytesSync(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('RENDU ${out.path} (${out.lengthSync()} octets)');
      });
    }
  });
}
