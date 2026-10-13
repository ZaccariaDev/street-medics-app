// Non-regression : la silhouette doit etre CENTREE dans son cadre.
//
// Bug constate a l'ecran sur le telephone : le corps apparaissait decale vers
// la droite, l'offset de centrage etant applique deux fois (une fois par le
// parent, une fois par une translation interne).
//
// Le test ne se contente pas de taper au centre (ce qui peut tomber juste par
// hasard) : il lit la position REELLEMENT RENDUE du SVG et la compare au cadre.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';
import 'package:street_medics_app/body_map_view.dart';

/// Monte le selecteur dans un cadre impose et rend son rect + celui du SVG.
Future<(Rect, Rect)> _layout(WidgetTester tester, double w, double h,
    BodyView view) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: w,
          height: h,
          child: BodyMapView(
            view: view,
            injuries: const [],
            zoomEnabled: false,
            onZoneTapped: (_) {},
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  // La vue de dos affiche DEUX SVG (calque de dos + silhouette de face).
  // La geometrie suit la silhouette de face : on prend le dernier.
  final svgs = find.byType(SvgPicture).evaluate().toList();
  return (
    tester.getRect(find.byType(BodyMapView)),
    tester.getRect(find.byWidget(svgs.last.widget as SvgPicture)),
  );
}

void main() {
  testWidgets('cadre large : la silhouette est centree horizontalement',
      (tester) async {
    final (frame, svg) = await _layout(tester, 400, 300, BodyView.front);
    expect((svg.center.dx - frame.center.dx).abs(), lessThan(1.0),
        reason: 'silhouette decalee de '
            '${(svg.center.dx - frame.center.dx).toStringAsFixed(1)} px : '
            'l\'offset de centrage est applique deux fois');
  });

  testWidgets('cadre etroit : la silhouette est centree verticalement',
      (tester) async {
    final (frame, svg) = await _layout(tester, 150, 700, BodyView.back);
    expect((svg.center.dy - frame.center.dy).abs(), lessThan(1.0),
        reason: 'silhouette decalee verticalement de '
            '${(svg.center.dy - frame.center.dy).toStringAsFixed(1)} px');
  });

  testWidgets('cadre carre : centrage horizontal ET vertical', (tester) async {
    for (final v in BodyView.values) {
      final (frame, svg) = await _layout(tester, 300, 300, v);
      expect((svg.center.dx - frame.center.dx).abs(), lessThan(1.0),
          reason: 'decalage horizontal en $v');
      expect((svg.center.dy - frame.center.dy).abs(), lessThan(1.0),
          reason: 'decalage vertical en $v');
    }
  });

  testWidgets('le SVG ne depasse jamais son cadre', (tester) async {
    // Le centrage ne doit pas se faire au prix d'un debordement.
    for (final (w, h) in [(400.0, 300.0), (150.0, 700.0), (300.0, 300.0)]) {
      final (frame, svg) = await _layout(tester, w, h, BodyView.front);
      expect(svg.left, greaterThanOrEqualTo(frame.left - 0.5));
      expect(svg.right, lessThanOrEqualTo(frame.right + 0.5));
      expect(svg.top, greaterThanOrEqualTo(frame.top - 0.5));
      expect(svg.bottom, lessThanOrEqualTo(frame.bottom + 0.5));
    }
  });
}
