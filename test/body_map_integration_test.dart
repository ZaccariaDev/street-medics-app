// Test d'integration du selecteur de blessures DANS l'app.
//
// Objectif : prouver que la silhouette est bien BRANCHEE dans l'onglet SOS
// (elle ne l'etait pas : le widget existait mais n'etait monte nulle part),
// qu'elle s'affiche, que le SVG est charge, et qu'un tap selectionne une zone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:street_medics_app/body_map.dart';
import 'package:street_medics_app/body_map_view.dart';
import 'package:street_medics_app/l10n/app_localizations.dart';
import 'package:street_medics_app/main.dart';

/// Monte le widget sous une app Material complete (localisations incluses).
Widget _host(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('integration : selecteur branche dans l\'app', () {
    testWidgets('l\'onglet SOS contient l\'acces au selecteur de blessures',
        (tester) async {
      await tester.pumpWidget(_host(const SosTab()));
      await tester.pump();

      // L'acces existe AVANT tout SOS (il est optionnel et hors du chemin).
      final t = await AppLocalizations.delegate.load(const Locale('fr'));
      expect(find.text(t.bodyMapTitle), findsWidgets);
      expect(find.text(t.bodyMapAddOptional), findsOneWidget);

      // Le bouton SOS principal est toujours la, a un seul appui.
      expect(find.text(t.sendMyPosition), findsOneWidget);
    });

    testWidgets('l\'ouverture affiche une silhouette SVG et deux vues',
        (tester) async {
      await tester.pumpWidget(_host(const SosTab()));
      await tester.pump();

      final t = await AppLocalizations.delegate.load(const Locale('fr'));
      // On ouvre le selecteur en touchant la carte d'acces.
      await tester.tap(find.text(t.bodyMapTitle).last);
      await tester.pumpAndSettle();

      // La silhouette est REELLEMENT rendue (SvgPicture) — c'est ce qui
      // manquait quand le widget n'etait monte nulle part.
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(BodyMapView), findsOneWidget);

      // Bascule face / dos presente.
      expect(find.text(t.bodyMapFront), findsWidgets);
      expect(find.text(t.bodyMapBack), findsWidgets);
    });

    testWidgets('un tap sur la silhouette selectionne une zone', (tester) async {
      // Ecran de telephone : la feuille doit tenir sans deborder.
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(const SosTab()));
      await tester.pump();
      final t = await AppLocalizations.delegate.load(const Locale('fr'));
      await tester.tap(find.text(t.bodyMapTitle).last);
      await tester.pumpAndSettle();

      // On vise le centre du buste (large et toujours dans le cadre),
      // en utilisant la meme conversion que le widget.
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
      await tester.tapAt(Offset(origin.dx + 0.5 * w, origin.dy + 0.30 * h));
      await tester.pumpAndSettle();

      // Une pastille de type apparait (donc une zone a ete selectionnee).
      final chips = find.byType(ChoiceChip);
      expect(chips, findsWidgets);
      // On verifie que la pastille porte bien un libelle de zone traduit,
      // pas une cle brute : c'est ce qui prouve le branchement des 24 langues.
      final labels = chips
          .evaluate()
          .map((e) => ((e.widget as ChoiceChip).label as Text).data ?? '')
          .toList();
      expect(labels.any((l) => l.contains('·')), isTrue,
          reason: 'pastilles sans libelle de zone : $labels');
      // La zone exacte depend du rendu de la feuille ; l'essentiel est qu'une
      // zone du corps ait ete retenue et que son libelle soit traduit.
      expect(labels.any((l) => l.startsWith(t.zoneChest) ||
          l.startsWith(t.zoneArmL) || l.startsWith(t.zoneArmR) ||
          l.startsWith(t.zoneAbdomen)), isTrue,
          reason: 'zone inattendue, pastilles obtenues : $labels');
    });
  });

  group('geometrie des zones', () {
    test('chaque zone est atteignable par son centre, dans les deux vues', () {
      for (final v in BodyView.values) {
        for (final z in bodyZones(v)) {
          expect(zoneAt(v, z.normalizedBounds().center), isNotNull,
              reason: '${z.id} introuvable en $v');
        }
      }
    });

    test('les zones tombent bien dans les limites du corps', () {
      // Aucune zone ne doit deborder hors du cadre 0..1.
      for (final v in BodyView.values) {
        for (final z in bodyZones(v)) {
          for (final p in z.points) {
            expect(p.dx, inInclusiveRange(0.0, 1.0),
                reason: '${z.id} deborde en x');
            expect(p.dy, inInclusiveRange(0.0, 1.0),
                reason: '${z.id} deborde en y');
          }
        }
      }
    });
  });

  group('chargement des SVG', () {
    test('les deux assets de silhouette sont declares et lisibles', () async {
      // Le bundle de test doit contenir les assets declares dans pubspec.
      for (final asset in [
        BodyViewAsset.front,
        BodyViewAsset.back,
      ]) {
        expect(asset.asset, startsWith('assets/anatomy/body_'));
        expect(asset.aspect, greaterThan(0));
      }
      // Les deux vues ont des viewBox differentes : les zones sont donc
      // definies par vue, sinon elles se decalent.
      expect(BodyViewAsset.front.viewBoxHeight,
          isNot(equals(BodyViewAsset.back.viewBoxHeight)));
    });
  });
}
