import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sélecteur de blessures sur silhouette.
///
/// Principe : la silhouette est définie dans un **espace logique normalisé**
/// (0..1) qui ne bouge jamais. Le zoom n'est qu'une transformation de rendu ;
/// les taps sont reconvertis dans l'espace logique par l'inverse de la matrice.
/// Sans cette séparation, la détection de zone se décale dès qu'on zoome —
/// c'est le piège classique du hit-testing sous transformation.
///
/// La silhouette EST l'union des zones : le dessin et la détection partagent
/// donc exactement les mêmes formes, ce qui rend impossible un décalage entre
/// ce qu'on voit et ce qu'on touche.

/// Vue affichée.
enum BodyView { front, back }

/// Une zone du corps, définie par un polygone en coordonnées normalisées.
class BodyZone {
  const BodyZone({
    required this.id,
    required this.labelKey,
    required this.points,
  });

  /// Identifiant stable, stocké côté serveur (`head`, `arm_l`, ...).
  final String id;

  /// Clé de traduction (les 23 langues de l'app).
  final String labelKey;

  /// Sommets du polygone, en 0..1 (origine en haut à gauche).
  final List<Offset> points;

  /// Convertit le polygone en `Path` pour une taille de dessin donnée.
  Path toPath(Size size) {
    final p = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(points[i].dx * size.width, points[i].dy * size.height);
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    return p..close();
  }

  /// Rectangle englobant, en coordonnées normalisées.
  Rect normalizedBounds() {
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final o in points) {
      minX = math.min(minX, o.dx);
      minY = math.min(minY, o.dy);
      maxX = math.max(maxX, o.dx);
      maxY = math.max(maxY, o.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Vrai si le point (espace normalisé) est dans la zone.
  ///
  /// Test par lancer de rayon : on compte les croisements d'une demi-droite
  /// horizontale partant du point. Impair = dedans. Fonctionne pour tout
  /// polygone simple (convexe ou non), sans dépendance externe.
  bool containsNormalized(Offset p) {
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final pi = points[i], pj = points[j];
      final intersects = ((pi.dy > p.dy) != (pj.dy > p.dy)) &&
          (p.dx <
              (pj.dx - pi.dx) * (p.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx);
      if (intersects) inside = !inside;
    }
    return inside;
  }
}

/// Génère un polygone approchant une ellipse (pour la tête).
List<Offset> _ellipse(double cx, double cy, double rx, double ry,
    {int segments = 16}) {
  return List<Offset>.generate(segments, (i) {
    final a = 2 * math.pi * i / segments;
    return Offset(cx + rx * math.cos(a), cy + ry * math.sin(a));
  });
}

/// Zones communes aux deux vues (membres, tête).
///
/// Dupliquées par vue plutôt que partagées : le dos a ses propres zones et une
/// future retouche d'une vue ne doit pas décaler l'autre.
List<BodyZone> _limbs() => [
      BodyZone(
        id: 'head',
        labelKey: 'zoneHead',
        points: _ellipse(0.5, 0.085, 0.055, 0.072),
      ),
      // Bras gauche du point de vue du spectateur.
      BodyZone(id: 'shoulder_l', labelKey: 'zoneShoulderL', points: const [
        Offset(0.310, 0.192), Offset(0.418, 0.166),
        Offset(0.444, 0.205), Offset(0.332, 0.232),
      ]),
      BodyZone(id: 'arm_l', labelKey: 'zoneArmL', points: const [
        Offset(0.332, 0.232), Offset(0.444, 0.205),
        Offset(0.418, 0.330), Offset(0.306, 0.348),
      ]),
      BodyZone(id: 'forearm_l', labelKey: 'zoneForearmL', points: const [
        Offset(0.306, 0.348), Offset(0.418, 0.330),
        Offset(0.398, 0.446), Offset(0.300, 0.458),
      ]),
      BodyZone(id: 'hand_l', labelKey: 'zoneHandL', points: const [
        Offset(0.300, 0.458), Offset(0.398, 0.446),
        Offset(0.388, 0.512), Offset(0.306, 0.520),
      ]),
      BodyZone(id: 'shoulder_r', labelKey: 'zoneShoulderR', points: const [
        Offset(0.690, 0.192), Offset(0.582, 0.166),
        Offset(0.556, 0.205), Offset(0.668, 0.232),
      ]),
      BodyZone(id: 'arm_r', labelKey: 'zoneArmR', points: const [
        Offset(0.668, 0.232), Offset(0.556, 0.205),
        Offset(0.582, 0.330), Offset(0.694, 0.348),
      ]),
      BodyZone(id: 'forearm_r', labelKey: 'zoneForearmR', points: const [
        Offset(0.694, 0.348), Offset(0.582, 0.330),
        Offset(0.602, 0.446), Offset(0.700, 0.458),
      ]),
      BodyZone(id: 'hand_r', labelKey: 'zoneHandR', points: const [
        Offset(0.700, 0.458), Offset(0.602, 0.446),
        Offset(0.612, 0.512), Offset(0.694, 0.520),
      ]),
      BodyZone(id: 'thigh_l', labelKey: 'zoneThighL', points: const [
        Offset(0.398, 0.502), Offset(0.497, 0.502),
        Offset(0.492, 0.682), Offset(0.408, 0.682),
      ]),
      BodyZone(id: 'shin_l', labelKey: 'zoneShinL', points: const [
        Offset(0.408, 0.682), Offset(0.492, 0.682),
        Offset(0.486, 0.858), Offset(0.418, 0.858),
      ]),
      BodyZone(id: 'foot_l', labelKey: 'zoneFootL', points: const [
        Offset(0.418, 0.858), Offset(0.486, 0.858),
        Offset(0.500, 0.922), Offset(0.406, 0.922),
      ]),
      BodyZone(id: 'thigh_r', labelKey: 'zoneThighR', points: const [
        Offset(0.503, 0.502), Offset(0.602, 0.502),
        Offset(0.592, 0.682), Offset(0.508, 0.682),
      ]),
      BodyZone(id: 'shin_r', labelKey: 'zoneShinR', points: const [
        Offset(0.508, 0.682), Offset(0.592, 0.682),
        Offset(0.582, 0.858), Offset(0.514, 0.858),
      ]),
      BodyZone(id: 'foot_r', labelKey: 'zoneFootR', points: const [
        Offset(0.514, 0.858), Offset(0.582, 0.858),
        Offset(0.594, 0.922), Offset(0.500, 0.922),
      ]),
    ];

/// Zones du tronc, propres à chaque vue.
List<BodyZone> _torso(BodyView view) {
  final neck = BodyZone(
    id: 'neck',
    labelKey: view == BodyView.front ? 'zoneNeck' : 'zoneNape',
    points: const [
      Offset(0.478, 0.148), Offset(0.522, 0.148),
      Offset(0.528, 0.190), Offset(0.472, 0.190),
    ],
  );
  final upper = BodyZone(
    id: view == BodyView.front ? 'chest' : 'back',
    labelKey: view == BodyView.front ? 'zoneChest' : 'zoneBack',
    points: const [
      Offset(0.472, 0.188), Offset(0.528, 0.188),
      Offset(0.596, 0.212), Offset(0.600, 0.310),
      Offset(0.590, 0.400), Offset(0.410, 0.400),
      Offset(0.400, 0.310), Offset(0.404, 0.212),
    ],
  );
  final lower = BodyZone(
    id: view == BodyView.front ? 'abdomen' : 'lower_back',
    labelKey: view == BodyView.front ? 'zoneAbdomen' : 'zoneLowerBack',
    points: const [
      Offset(0.410, 0.402), Offset(0.590, 0.402),
      Offset(0.600, 0.498), Offset(0.400, 0.498),
    ],
  );
  return [neck, upper, lower];
}

/// Toutes les zones d'une vue, dans l'ordre de dessin.
List<BodyZone> bodyZones(BodyView view) => [..._torso(view), ..._limbs()];

/// Retrouve la zone sous un point normalisé (null si hors du corps).
BodyZone? zoneAt(BodyView view, Offset normalized) {
  // Parcours inversé : les membres sont dessinés après le tronc, donc une
  // zone tardive doit gagner en cas de chevauchement (ex. épaule/bras).
  final zones = bodyZones(view);
  for (final z in zones.reversed) {
    if (z.containsNormalized(normalized)) return z;
  }
  return null;
}

/// Type de blessure.
///
/// Liste MINIMALE en attendant celle du street medic : la remplacer ici suffit
/// (aucun autre fichier à toucher).
class InjuryType {
  const InjuryType(this.id, this.labelKey, this.color);
  final String id;
  final String labelKey;
  final Color color;
}

const List<InjuryType> kInjuryTypes = [
  InjuryType('wound', 'injuryWound', Color(0xFFD32F2F)), // plaie / hémorragie
  InjuryType('fracture', 'injuryFracture', Color(0xFF1976D2)), // fracture
  InjuryType('burn', 'injuryBurn', Color(0xFFE64A19)), // brûlure
  InjuryType('other', 'injuryOther', Color(0xFF616161)), // autre
];

/// Une blessure : une zone et son type.
class Injury {
  const Injury({required this.zoneId, required this.typeId});
  final String zoneId;
  final String typeId;

  Map<String, dynamic> toJson() => {'zone': zoneId, 'type': typeId};
  static Injury fromJson(Map<String, dynamic> j) => Injury(
        zoneId: j['zone']?.toString() ?? '',
        typeId: j['type']?.toString() ?? '',
      );
}
