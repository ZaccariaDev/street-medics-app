// Ecran de confirmation apres l'envoi d'un SOS, et premiers gestes.
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';
import 'package:street_medics_app/first_aid.dart';

void main() {
  group('premiers gestes (contenu provisoire)', () {
    test('chaque type de blessure a une conduite a tenir', () {
      for (final type in kInjuryTypes) {
        final aid = firstAidFor(type.id);
        expect(aid.typeId, type.id,
            reason: 'aucune conduite a tenir pour ${type.id}');
        expect(aid.stepsKey, startsWith('aid'));
      }
    });

    test('un type inconnu retombe sur « autre », sans planter', () {
      final aid = firstAidFor('type-qui-nexiste-pas');
      expect(aid.typeId, 'other');
    });

    test('le contenu est marque comme provisoire', () {
      // L'association doit fournir la version reelle : le code le signale,
      // pour qu'on ne prenne pas ce contenu pour une consigne validee.
      expect(kFirstAidIsStub, isTrue);
    });
  });

  group('etapes affichables', () {
    /// Reproduit le decoupage fait par l'app (une etape par ligne).
    List<String> steps(String raw) => raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    test('le decoupage en etapes donne des lignes non vides', () {
      // On verifie le mecanisme sur un exemple representatif.
      const raw = 'Premiere etape\nDeuxieme etape\n\nTroisieme etape';
      final out = steps(raw);
      expect(out.length, 3);
      expect(out, ['Premiere etape', 'Deuxieme etape', 'Troisieme etape']);
    });

    test('une chaine vide ne produit aucune etape', () {
      expect(steps(''), isEmpty);
      expect(steps('\n\n'), isEmpty);
    });
  });

  group('injury', () {
    test('une blessure non urgente n\'est pas signalee comme telle', () {
      // « other » ne porte pas de drapeau urgent : pas de dramatisation.
      expect(firstAidFor('other').urgent, isFalse);
      // Plaie et brulure imposent d'alerter.
      expect(firstAidFor('wound').urgent, isTrue);
      expect(firstAidFor('burn').urgent, isTrue);
    });

    test('la serialisation des blessures reste stable', () {
      const i = Injury(zoneId: 'head', typeId: 'wound');
      expect(i.toJson(), {'zone': 'head', 'type': 'wound'});
      expect(Injury.fromJson(i.toJson()).zoneId, 'head');
    });
  });
}
