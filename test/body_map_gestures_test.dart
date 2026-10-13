// Gestes de zoom : double-tap et pincement.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';
import 'package:street_medics_app/body_map_view.dart';

/// Recupere le facteur de zoom courant du widget.
double scaleOf(WidgetTester tester) {
  final state = tester.state<BodyMapViewState>(find.byType(BodyMapView));
  // Le facteur se lit dans la matrice de rendu : on lit directement l'etat.
  return state.debugScale;
}

void main() {
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 620,
            child: BodyMapView(
              view: BodyView.front,
              injuries: const [],
              onZoneTapped: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('un double-tap zoome', (tester) async {
    await mount(tester);
    expect(scaleOf(tester), closeTo(1.0, 0.01));

    final box = tester.getRect(find.byType(BodyMapView));
    // Double-tap au centre.
    await tester.tapAt(box.center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(box.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(scaleOf(tester), greaterThan(1.4),
        reason: 'le double-tap doit zoomer (facteur obtenu : '
            '${scaleOf(tester)})');
  });

  testWidgets('un pincement qui ecarte zoome', (tester) async {
    await mount(tester);
    final box = tester.getRect(find.byType(BodyMapView));

    // Deux doigts qui s'ecartent du centre.
    final a = await tester.startGesture(box.center - const Offset(20, 0));
    final b = await tester.startGesture(box.center + const Offset(20, 0));
    await tester.pump();
    for (var i = 1; i <= 8; i++) {
      await a.moveTo(box.center - Offset(20.0 + i * 12, 0));
      await b.moveTo(box.center + Offset(20.0 + i * 12, 0));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(scaleOf(tester), greaterThan(1.3),
        reason: 'le pincement doit zoomer (facteur obtenu : '
            '${scaleOf(tester)})');
  });

  testWidgets('le zoom est borne', (tester) async {
    await mount(tester);
    final box = tester.getRect(find.byType(BodyMapView));

    // Pincement enorme : le facteur doit rester borne.
    final a = await tester.startGesture(box.center - const Offset(10, 0));
    final b = await tester.startGesture(box.center + const Offset(10, 0));
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(box.center - Offset(10.0 + i * 40, 0));
      await b.moveTo(box.center + Offset(10.0 + i * 40, 0));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(scaleOf(tester), lessThanOrEqualTo(3.01),
        reason: 'le zoom ne doit pas depasser le maximum');
  });

  testWidgets('le tap simple selectionne toujours une zone', (tester) async {
    final touched = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 620,
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

    final box = tester.getRect(find.byType(BodyMapView));
    final asset = BodyViewAsset.front;
    var w = box.width;
    var h = w / asset.aspect;
    if (h > box.height) {
      h = box.height;
      w = h * asset.aspect;
    }
    final origin =
        Offset(box.left + (box.width - w) / 2, box.top + (box.height - h) / 2);

    // Le buste.
    await tester.tapAt(Offset(origin.dx + 0.5 * w, origin.dy + 0.35 * h));
    // Laisse s'ecouler le retour visuel PUIS tout autre timer eventuel :
    // sinon le test echoue sur « Timer is still pending », pas sur la zone.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(touched, contains('chest'),
        reason: 'le tap simple doit encore selectionner (obtenu: $touched)');
  });
}
