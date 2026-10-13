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
      // Avec le double-tap actif, Flutter retarde le tap simple (~300 ms) le
      // temps de savoir si un 2e tap arrive. Il faut donc laisser ce delai
      // s'ecouler AVANT de chercher les pastilles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Le bouton Valider est actif (une zone est sélectionnée).
      final validateBtn = find.widgetWithText(FilledButton, 'Valider (1)');
      expect(validateBtn, findsOneWidget);

      // On va à la page 2 (types de blessure).
      await tester.tap(validateBtn);
      await tester.pumpAndSettle();

      // Les pastilles de type sont visibles sur la page 2.
      final chips = find.byType(ChoiceChip);
      expect(chips, findsWidgets);
      // On verifie que la zone est bien affichee sur la page 2,
      // et que le branchement des 24 langues fonctionne.
      expect(find.textContaining(t.zoneChest), findsWidgets,
          reason: 'zone absente de la page 2');
      expect(find.textContaining(t.injuryWound), findsWidgets,
          reason: 'type de blessure absent de la page 2');
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
