// J5 : verifie EXACTEMENT ce qui part sur le reseau pour un SOS.
//
// On ne peut pas interroger le vrai PocketBase depuis un test unitaire. En
// revanche `PbService.reportBody` est une fonction pure : on peut donc
// verifier le corps de requete octet par octet, ce qui est la seule partie
// dont l'app est responsable.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';
import 'package:street_medics_app/pb_service.dart';

void main() {
  group('J5 : corps envoye au serveur', () {
    test('SOS simple : le champ injuries est ABSENT', () {
      // Le parcours d'urgence (un appui) ne doit rien ajouter a la requete.
      final body = PbService.reportBody(
        lat: 48.8566,
        lng: 2.3522,
        description: 'SOS',
      );
      expect(body.containsKey('injuries'), isFalse,
          reason: 'un SOS simple ne doit pas porter de blessures');
      expect(body['status'], 'open');
      expect(body['description'], 'SOS');
      expect(body['position'], {'lat': 48.8566, 'lng': 2.3522});
    });

    test('SOS avec blessures : structure conforme a la migration serveur', () {
      // La migration serveur attend : { view, zones: [{zone, type}] }
      final body = PbService.reportBody(
        lat: 48.8566,
        lng: 2.3522,
        description: 'Chute',
        senderPhone: '+33612345678',
        injuries: const [
          Injury(zoneId: 'head', typeId: 'wound'),
          Injury(zoneId: 'forearm_l', typeId: 'fracture'),
        ],
        injuriesView: BodyView.front,
      );
      // Passe par JSON : c'est la forme qui part reellement sur le reseau.
      final sent = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
      final inj = sent['injuries'] as Map<String, dynamic>;
      expect(inj['view'], 'front');
      final zones = inj['zones'] as List;
      expect(zones.length, 2);
      expect(zones[0], {'zone': 'head', 'type': 'wound'});
      expect(zones[1], {'zone': 'forearm_l', 'type': 'fracture'});
    });

    test('la vue de dos est transmise telle quelle', () {
      final body = PbService.reportBody(
        lat: 1,
        lng: 2,
        description: 'SOS',
        injuries: const [Injury(zoneId: 'back', typeId: 'burn')],
        injuriesView: BodyView.back,
      );
      expect((body['injuries'] as Map)['view'], 'back');
    });

    test('sans vue precise, on retombe sur la face', () {
      final body = PbService.reportBody(
        lat: 1,
        lng: 2,
        description: 'SOS',
        injuries: const [Injury(zoneId: 'head', typeId: 'wound')],
      );
      expect((body['injuries'] as Map)['view'], 'front');
    });

    test('toutes les zones des deux vues sont serialisables', () {
      // Garantit qu'aucune zone du selecteur ne produit un envoi invalide.
      for (final v in BodyView.values) {
        final injuries = [
          for (final z in bodyZones(v)) Injury(zoneId: z.id, typeId: 'wound'),
        ];
        final body = PbService.reportBody(
          lat: 1,
          lng: 2,
          description: 'SOS',
          injuries: injuries,
          injuriesView: v,
        );
        final sent = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
        final zones = (sent['injuries'] as Map)['zones'] as List;
        expect(zones.length, injuries.length);
        for (final z in zones) {
          expect((z as Map)['zone'], isNotEmpty);
          expect(z['type'], isNotEmpty);
        }
      }
    });

    test('le corps tient dans la limite de 4000 octets de la migration', () {
      // La migration borne le champ a 4000 octets : on verifie que meme le
      // pire cas (toutes les zones des deux vues) reste sous la limite.
      final injuries = [
        for (final v in BodyView.values)
          for (final z in bodyZones(v)) Injury(zoneId: z.id, typeId: 'fracture'),
      ];
      final body = PbService.reportBody(
        lat: 48.8566,
        lng: 2.3522,
        description: 'SOS',
        injuries: injuries,
        injuriesView: BodyView.front,
      );
      final size = jsonEncode(body['injuries']).length;
      expect(size, lessThan(4000),
          reason: 'le champ injuries ferait $size octets, '
              'au-dessus de la limite serveur');
    });
  });
}
