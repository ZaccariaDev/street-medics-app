// Preuve que CHAQUE zone du corps est REELLEMENT touchable dans le widget.
//
// Le test unitaire valide la geometrie (un point appartient a un polygone) mais
// pas le branchement : conversion ecran -> normalise, letterboxing, ordre de
// superposition des zones. C'est cette couche qui cachait deux bugs reels :
//   - le haut du corps sortait du cadre (feuille qui debordait) ;
//   - les epaules etaient recouvertes par le polygone du bras.
// On tape donc sur le centre de chaque zone, via le vrai widget.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';
import 'package:street_medics_app/body_map_view.dart';

void main() {
  testWidgets('chaque zone est touchable dans le widget reel (2 vues)',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    for (final v in BodyView.values) {
      final touched = <String>{};
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 474,
              child: BodyMapView(
                view: v,
                injuries: const [],
                zoomEnabled: false,
                onZoneTapped: (z) => touched.add(z.id),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final r = tester.getRect(find.byType(BodyMapView));
      final asset = BodyViewAsset.of(v);
      var w = r.width;
      var h = w / asset.aspect;
      if (h > r.height) {
        h = r.height;
        w = h * asset.aspect;
      }
      final origin =
          Offset(r.left + (r.width - w) / 2, r.top + (r.height - h) / 2);

      for (final z in bodyZones(v)) {
        final c = z.normalizedBounds().center;
        touched.clear();
        await tester.tapAt(
            Offset(origin.dx + c.dx * w, origin.dy + c.dy * h));
        // Laisse s'ecouler le retour visuel (220 ms) : sans cela le test
        // echoue sur un timer en attente, pas sur la geometrie.
        await tester.pump(const Duration(milliseconds: 300));
        expect(touched, contains(z.id),
            reason: 'zone ${z.id} intouchable en $v '
                '(obtenu: ${touched.isEmpty ? "rien" : touched.join(",")})');
      }
    }
  });

  testWidgets('aucune zone n\'est masquee par une autre (priorite stable)',
      (tester) async {
    // Chaque zone doit gagner sur son propre centre : c'est ce qui garantit
    // qu'aucune n'est recouverte par un polygone dessine par-dessus.
    for (final v in BodyView.values) {
      for (final z in bodyZones(v)) {
        final hit = zoneAt(v, z.normalizedBounds().center);
        expect(hit?.id, z.id,
            reason: 'le centre de ${z.id} renvoie ${hit?.id} en $v');
      }
    }
  });

  testWidgets('un tap hors du corps ne selectionne rien', (tester) async {
    final touched = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 220,
            height: 474,
            child: BodyMapView(
              view: BodyView.front,
              injuries: const [],
              zoomEnabled: false,
              onZoneTapped: (z) => touched.add(z.id),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    final r = tester.getRect(find.byType(BodyMapView));
    // Coins : vides dans les deux vues.
    await tester.tapAt(Offset(r.left + 4, r.top + 4));
    await tester.tapAt(Offset(r.right - 4, r.bottom - 4));
    await tester.pump();
    expect(touched, isEmpty);
  });
}
