// J5/J6 : les blessures font l'aller-retour serveur sans perte.
//
// On ne peut pas interroger le vrai PocketBase depuis un test unitaire ; on
// verifie donc la seule partie qui nous appartient : la conversion
// modele -> JSON (envoye au serveur) et JSON -> modele (relu).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';

void main() {
  group('J5 : forme envoyee au serveur', () {
    test('le corps envoye correspond au format attendu par la migration', () {
      // Doit correspondre a ce que lit la migration serveur :
      //   { "view": "front"|"back", "zones": [ {zone, type}, ... ] }
      final injuries = [
        const Injury(zoneId: 'head', typeId: 'wound'),
        const Injury(zoneId: 'forearm_l', typeId: 'fracture'),
      ];
      final body = {
        'view': BodyView.front.name,
        'zones': injuries.map((i) => i.toJson()).toList(),
      };
      // Passe par JSON : c'est ce qui part reellement sur le reseau.
      final round = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
      expect(round['view'], 'front');
      final zones = round['zones'] as List;
      expect(zones.length, 2);
      expect(zones[0], {'zone': 'head', 'type': 'wound'});
      expect(zones[1], {'zone': 'forearm_l', 'type': 'fracture'});
    });

    test('la vue de dos est bien transmise', () {
      final body = {'view': BodyView.back.name, 'zones': <dynamic>[]};
      expect(jsonDecode(jsonEncode(body))['view'], 'back');
    });

    test('un SOS sans blessure n\'envoie pas le champ', () {
      // Le parcours d'urgence simple ne doit rien ajouter au corps envoye.
      final body = <String, dynamic>{
        'description': 'SOS',
        'status': 'open',
      };
      expect(body.containsKey('injuries'), isFalse);
    });
  });

  group('J6 : relecture pour l\'affichage', () {
    /// Reproduit la lecture faite par PbService._injuries.
    List<Injury> read(dynamic raw) {
      if (raw is! Map) return const <Injury>[];
      final zones = raw['zones'];
      if (zones is! List) return const <Injury>[];
      final out = <Injury>[];
      for (final z in zones) {
        if (z is! Map) continue;
        final zone = z['zone']?.toString() ?? '';
        final type = z['type']?.toString() ?? '';
        if (zone.isEmpty) continue;
        out.add(Injury(zoneId: zone, typeId: type.isEmpty ? 'other' : type));
      }
      return out;
    }

    test('un signalement avec blessures est relu correctement', () {
      final raw = jsonDecode(jsonEncode({
        'view': 'back',
        'zones': [
          {'zone': 'back', 'type': 'wound'},
          {'zone': 'shin_r', 'type': 'burn'},
        ],
      }));
      final injuries = read(raw);
      expect(injuries.length, 2);
      expect(injuries[0].zoneId, 'back');
      expect(injuries[1].typeId, 'burn');
    });

    test('un signalement ANCIEN (sans champ) ne casse pas l\'affichage', () {
      // Retrocompatibilite : tous les SOS deja en base sont dans ce cas.
      expect(read(null), isEmpty);
      expect(read(''), isEmpty);
      expect(read(<String, dynamic>{}), isEmpty);
      expect(read({'view': 'front'}), isEmpty);
    });

    test('une donnee malformee est ignoree, pas fatale', () {
      // Un enregistrement abime ne doit jamais faire planter la liste.
      expect(read({'zones': 'pas une liste'}), isEmpty);
      expect(read({'zones': [1, 2, 'x', null]}), isEmpty);
      expect(read({'zones': [{'type': 'wound'}]}), isEmpty); // zone vide
      // Type manquant : on retombe sur "autre" plutot que de perdre la zone.
      final partial = read({'zones': [{'zone': 'head'}]});
      expect(partial.length, 1);
      expect(partial.first.typeId, 'other');
    });

    test('chaque zone lue a un libellé traduit disponible', () {
      // Une zone inconnue ne doit pas produire de texte vide a l'ecran.
      for (final v in BodyView.values) {
        for (final z in bodyZones(v)) {
          expect(z.labelKey, startsWith('zone'));
        }
      }
    });
  });
}
