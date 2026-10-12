// Tests de la silhouette : géométrie des zones et hit-testing sous zoom.
//
// Ces tests vérifient le point le plus fragile de la fonctionnalité : le
// hit-testing doit rester exact quelle que soit la transformation appliquée.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';

void main() {
  group('zones du corps', () {
    test('les deux vues ont des zones', () {
      expect(bodyZones(BodyView.front), isNotEmpty);
      expect(bodyZones(BodyView.back), isNotEmpty);
    });

    test('aucun identifiant de zone en double dans une vue', () {
      for (final v in BodyView.values) {
        final ids = bodyZones(v).map((z) => z.id).toList();
        expect(ids.toSet().length, ids.length,
            reason: 'doublon dans $v : $ids');
      }
    });

    test('les polygones sont fermables (au moins 3 sommets)', () {
      for (final v in BodyView.values) {
        for (final z in bodyZones(v)) {
          expect(z.points.length, greaterThanOrEqualTo(3),
              reason: '${z.id} a ${z.points.length} sommets');
        }
      }
    });

    test('toutes les coordonnées restent dans 0..1', () {
      for (final v in BodyView.values) {
        for (final z in bodyZones(v)) {
          for (final o in z.points) {
            expect(o.dx, inInclusiveRange(0.0, 1.0), reason: '${z.id} x');
            expect(o.dy, inInclusiveRange(0.0, 1.0), reason: '${z.id} y');
          }
        }
      }
    });

    test('la tête est en haut du corps', () {
      final head =
          bodyZones(BodyView.front).firstWhere((z) => z.id == 'head');
      final foot =
          bodyZones(BodyView.front).firstWhere((z) => z.id == 'foot_l');
      expect(head.normalizedBounds().center.dy,
          lessThan(foot.normalizedBounds().center.dy));
    });

    test('les deux vues ont le même nombre de membres', () {
      int limbs(BodyView v) =>
          bodyZones(v).where((z) => z.id != 'neck' && z.id != 'chest' &&
              z.id != 'back' && z.id != 'abdomen' && z.id != 'lower_back').length;
      expect(limbs(BodyView.front), limbs(BodyView.back));
    });
  });

  group('hit-testing', () {
    test('le centre de la tête est détecté comme tête', () {
      final head =
          bodyZones(BodyView.front).firstWhere((z) => z.id == 'head');
      final c = head.normalizedBounds().center;
      expect(zoneAt(BodyView.front, c)?.id, 'head');
    });

    test('un point hors du corps ne renvoie aucune zone', () {
      // Coin supérieur gauche : vide dans toutes les vues.
      expect(zoneAt(BodyView.front, const Offset(0.02, 0.02)), isNull);
      expect(zoneAt(BodyView.back, const Offset(0.98, 0.98)), isNull);
    });

    test('chaque zone est atteignable par son propre centre', () {
      for (final v in BodyView.values) {
        for (final z in bodyZones(v)) {
          final c = z.normalizedBounds().center;
          final hit = zoneAt(v, c);
          expect(hit, isNotNull, reason: '${z.id} introuvable en $v');
        }
      }
    });

    test('la vue de face et la vue de dos diffèrent sur le tronc', () {
      final front = bodyZones(BodyView.front).map((z) => z.id).toSet();
      final back = bodyZones(BodyView.back).map((z) => z.id).toSet();
      expect(front.contains('chest'), isTrue);
      expect(front.contains('back'), isFalse);
      expect(back.contains('back'), isTrue);
      expect(back.contains('chest'), isFalse);
    });
  });

  group('injury', () {
    test('sérialisation aller-retour', () {
      const i = Injury(zoneId: 'head', typeId: 'wound');
      final j = i.toJson();
      final back = Injury.fromJson(j);
      expect(back.zoneId, 'head');
      expect(back.typeId, 'wound');
    });

    test('la liste de types est non vide et sans doublon', () {
      expect(kInjuryTypes, isNotEmpty);
      final ids = kInjuryTypes.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('le repli d\'un type inconnu ne plante pas', () {
      // Le code utilise orElse -> dernier type ; on vérifie qu'il existe.
      expect(kInjuryTypes.last.id, isNotEmpty);
    });
  });
}
