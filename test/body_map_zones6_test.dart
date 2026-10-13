// Les SIX parties du corps : structure et hit-testing.
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';

void main() {
  group('les six parties du corps', () {
    test('au total 6 parties, dont 5 cliquables dans chaque vue', () {
      // Les parties paires (epaules, bras, jambes) se dessinent en DEUX
      // polygones : on compte les libelles, pas les polygones.
      //
      // Le tronc est « buste » de face et « dos » de dos : une seule des deux
      // par vue, sinon elles se masqueraient (meme surface).
      final toutes = <String>{};
      for (final v in BodyView.values) {
        final labels = bodyZones(v).map((z) => z.labelKey).toSet();
        expect(labels.length, 5,
            reason: 'la vue $v doit offrir 5 parties cliquables, '
                'pas ${labels.length} : $labels');
        toutes.addAll(labels);
      }
      expect(toutes.length, 6,
          reason: 'au total, 6 parties distinctes : $toutes');
    });

    test('les 5 parties communes sont presentes dans les deux vues', () {
      for (final v in BodyView.values) {
        final ids = bodyZones(v).map((z) => z.id).toSet();
        for (final commun in ['head', 'shoulder_l', 'shoulder_r',
            'arm_l', 'arm_r', 'leg_l', 'leg_r']) {
          expect(ids, contains(commun), reason: '$commun absent en $v');
        }
      }
    });

    test('le tronc est « buste » de face et « dos » de dos, jamais les deux',
        () {
      final front = bodyZones(BodyView.front).map((z) => z.id).toSet();
      final back = bodyZones(BodyView.back).map((z) => z.id).toSet();
      // Les deux occupent la meme surface : les cumuler masquerait l'autre.
      expect(front, contains('chest'));
      expect(front, isNot(contains('back')));
      expect(back, contains('back'));
      expect(back, isNot(contains('chest')));
    });

    test('chaque partie a un libellé traduit dédié', () {
      final keys = bodyZones(BodyView.front)
          .map((z) => z.labelKey)
          .toSet();
      // 6 parties => 6 cles distinctes (les paires gauche/droite partagent).
      expect(keys.length, 5, reason: 'cles : $keys');
      for (final k in keys) {
        expect(k, startsWith('zone'));
      }
    });

    test('chaque partie est atteignable par son propre centre', () {
      for (final v in BodyView.values) {
        for (final z in bodyZones(v)) {
          final hit = zoneAt(v, z.normalizedBounds().center);
          expect(hit?.id, z.id,
              reason: 'le centre de ${z.id} renvoie ${hit?.id} en $v');
        }
      }
    });

    test('aucune partie ne déborde du cadre 0..1', () {
      for (final v in BodyView.values) {
        for (final z in bodyZones(v)) {
          for (final p in z.points) {
            expect(p.dx, inInclusiveRange(0.0, 1.0));
            expect(p.dy, inInclusiveRange(0.0, 1.0));
          }
        }
      }
    });

    test('hors du corps, aucune partie n\'est détectée', () {
      expect(zoneAt(BodyView.front, const Offset(0.02, 0.02)), isNull);
      expect(zoneAt(BodyView.back, const Offset(0.98, 0.02)), isNull);
    });

    test('le centre du corps (entre les jambes) ne renvoie rien', () {
      // Deux jambes distinctes : le milieu est vide, c'est normal.
      expect(zoneAt(BodyView.front, const Offset(0.5, 0.90)), isNull);
    });
  });
}
