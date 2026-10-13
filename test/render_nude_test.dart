// Rend la silhouette SANS aucun marquage, pour mesurer sa forme reelle.
//
// Le rendu avec blessures colorees decoupe le corps en segments (les pixels
// satures sont exclus de la mesure). Ici : silhouette nue, mesurable.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';
import 'package:street_medics_app/body_map_view.dart';

void main() {
  testWidgets('silhouette nue (face et dos)', (tester) async {
    tester.view.physicalSize = const Size(600, 1240);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final v in BodyView.values) {
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
                  injuries: const [], // AUCUN marquage
                  zoomEnabled: false,
                  onZoneTapped: (_) {},
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('shot')));
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        final f = File('/tmp/nude_${v.name}.png');
        f.writeAsBytesSync(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('NU ${f.path} (${f.lengthSync()} octets)');
      });
    }
  });
}
