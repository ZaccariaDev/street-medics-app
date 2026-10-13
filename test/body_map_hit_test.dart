// Preuve que CHAQUE partie du corps est REELLEMENT touchable dans le widget.
//
// Le test unitaire valide la geometrie (un point appartient a un polygone) mais
// pas le branchement : conversion ecran -> normalise, letterboxing, ordre de
// superposition des zones. C'est cette couche qui a cache plusieurs bugs reels
// (haut du corps hors cadre, epaules recouvertes par le bras, silhouette
// decalee par un double centrage).
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';
import 'package:street_medics_app/body_map_view.dart';

void main() {
  testWidgets('chaque partie est touchable dans le widget reel (2 vues)',
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
      // La geometrie suit TOUJOURS la silhouette de face.
      final asset = BodyViewAsset.front;
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
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(touched, contains(z.id),
            reason: 'partie ${z.id} intouchable en $v '
                '(obtenu: ${touched.isEmpty ? "rien" : touched.join(",")})');
      }
    }
  });

  testWidgets('aucune partie n\'est masquee par une autre (priorite stable)',
      (tester) async {
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
    await tester.tapAt(Offset(r.left + 4, r.top + 4));
    await tester.pump();
        await tester.pump(const Duration(seconds: 2));
    expect(touched, isEmpty);
  });

  testWidgets('la vue de dos affiche un calque supplementaire, sans rotation',
      (tester) async {
    // Face : une seule silhouette.
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
              onZoneTapped: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(SvgPicture), findsOneWidget,
        reason: 'de face : une seule silhouette');

    // Dos : la silhouette de face PLUS le calque de dos derriere.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 220,
            height: 474,
            child: BodyMapView(
              view: BodyView.back,
              injuries: const [],
              zoomEnabled: false,
              onZoneTapped: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(SvgPicture), findsNWidgets(2),
        reason: 'de dos : silhouette + calque de dos derriere');

    // Le calque de dos est bien en retrait (60 %).
    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .toList();
    expect(opacities, contains(0.6),
        reason: 'le calque de dos doit etre a 60 % d\'opacite');

    // Et la silhouette de face n'est jamais retiree : le bonhomme ne pivote pas.
    final svgs = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
    final assets = svgs.map((s) => s.bytesLoader).toList();
    expect(assets.length, 2);
  });
}
