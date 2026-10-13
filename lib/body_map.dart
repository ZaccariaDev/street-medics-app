import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sélecteur de blessures sur silhouette anatomique.
///
/// **Image** : silhouette humaine asexuée, CC0 (domaine public), rendue par
/// `flutter_svg` depuis `assets/anatomy/body_front.svg` et `body_back.svg`.
///
/// **Six parties du corps** : tête, épaules, buste, bras, jambes, dos. Les
/// zones fines (avant-bras, main, cuisse, mollet, pied) ont été fusionnées :
/// sur le terrain on désigne « le bras », pas « l'avant-bras gauche ».
///
/// **Le dos est un calque derrière la silhouette**, pas une seconde vue. Le
/// bouton « Dos » ne fait donc pas pivoter le bonhomme : il révèle la
/// silhouette de dos, en retrait (60 % d'opacité), par-dessus laquelle on
/// marque la zone « dos ».
///
/// **Zones** : polygones INVISIBLES superposés à l'image, en coordonnées
/// normalisées (0..1). Cette séparation permet d'avoir une belle illustration
/// *et* un hit-testing exact, sans dépendre du découpage interne du SVG.
///
/// **Zoom** : la géométrie ne bouge jamais ; le zoom n'est qu'une
/// transformation de rendu, et les taps sont reconvertis par l'inverse de la
/// matrice. Sans cela la détection se décale dès qu'on zoome.

/// Ce que l'on est en train de désigner.
enum BodyView {
  /// Parties visibles de face.
  front,

  /// Le dos, révélé derrière la silhouette (pas une rotation).
  back,
}

/// Dimensions natives des SVG (viewBox) — différentes entre les deux vues !
/// Les zones sont définies par vue pour cette raison.
class BodyViewAsset {
  const BodyViewAsset(this.asset, this.viewBoxWidth, this.viewBoxHeight);
  final String asset;
  final double viewBoxWidth;
  final double viewBoxHeight;

  static const BodyViewAsset front =
      BodyViewAsset('assets/anatomy/body_front.svg', 147.998, 318.455);
  static const BodyViewAsset back =
      BodyViewAsset('assets/anatomy/body_back.svg', 147.998, 314.861);

  double get aspect => viewBoxWidth / viewBoxHeight;

  static BodyViewAsset of(BodyView v) =>
      v == BodyView.front ? front : back;
}

/// Une zone du corps, définie par un polygone en coordonnées normalisées.
class BodyZone {
  const BodyZone({
    required this.id,
    required this.labelKey,
    required this.points,
  });

  /// Identifiant stable, stocké côté serveur (`head`, `back`, ...).
  final String id;

  /// Clé de traduction (les 24 langues de l'app).
  final String labelKey;

  /// Sommets du polygone, en 0..1 (origine en haut à gauche).
  final List<Offset> points;

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

  /// Test d'appartenance par lancer de rayon (polygones quelconques).
  bool containsNormalized(Offset p) {
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final pi = points[i], pj = points[j];
      final crosses = ((pi.dy > p.dy) != (pj.dy > p.dy)) &&
          (p.dx <
              (pj.dx - pi.dx) * (p.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx);
      if (crosses) inside = !inside;
    }
    return inside;
  }
}

/// Polygone trapézoïdal (membres qui s'affinent, épaules obliques).
List<Offset> _trap(double tl, double tr, double bl, double br, double t,
        double b) =>
    [Offset(tl, t), Offset(tr, t), Offset(br, b), Offset(bl, b)];

/// Ellipse approchée (tête, mains, pieds).
List<Offset> _ellipse(double cx, double cy, double rx, double ry,
        {int segments = 18}) =>
    List<Offset>.generate(segments, (i) {
      final a = 2 * math.pi * i / segments;
      return Offset(cx + rx * math.cos(a), cy + ry * math.sin(a));
    });

/// Les SIX parties du corps, calibrées sur la silhouette RÉELLE.
///
/// Mesures relevées sur le rendu nu (`/tmp/nude_front.png`), segments de corps
/// par hauteur. Repères :
///   tête       y 0.00-0.14   x 0.40-0.60 (plus large à 0.05)
///   épaules    y 0.155-0.32  x 0.20-0.42 (G) et 0.58-0.80 (D)
///   tronc      y 0.155-0.58  x 0.31-0.69 en haut, 0.26-0.74 en bas
///   bras       y 0.32-0.58   x 0.115-0.28 (G), 0.72-0.885 (D) — DÉTACHÉS du
///                            tronc (il y a un vide entre les deux)
///   jambes     y 0.58-0.98   x 0.26-0.48 (G), 0.52-0.74 (D)
///
/// **Pourquoi les épaules étaient imprenables** : elles formaient un mince
/// bandeau (0.145 de haut) placé SOUS le haut des bras, lequel était dessiné
/// par-dessus. Le centre de l'épaule tombait donc dans la zone bras. Elles
/// couvrent maintenant tout le haut du corps (y 0.155-0.32) et les bras
/// commencent EN DESSOUS.
///
/// **Pourquoi le bras gauche était « non superposé »** : sa zone
/// (x 0.18-0.33 en haut) était décalée vers le tronc, alors que le bras réel
/// est à x 0.115-0.28. Mesuré : le centre de la zone tombait HORS du corps.
List<BodyZone> bodyZones(BodyView view) => [
      // Tête : ellipse du crâne (mesuré x 0.40-0.60 à y 0.05).
      BodyZone(id: 'head', labelKey: 'zoneHead',
          points: _ellipse(0.5, 0.078, 0.090, 0.072)),
      // Épaules : larges, tout le haut du corps, de part et d'autre du cou.
      BodyZone(id: 'shoulder_l', labelKey: 'zoneShoulders',
          points: _trap(0.200, 0.420, 0.230, 0.350, 0.155, 0.320)),
      BodyZone(id: 'shoulder_r', labelKey: 'zoneShoulders',
          points: _trap(0.580, 0.800, 0.650, 0.770, 0.155, 0.320)),
      // Tronc : « buste » de face, « dos » quand on désigne l'arrière.
      // Jamais les deux : ils occupent la même surface.
      if (view == BodyView.front)
        BodyZone(id: 'chest', labelKey: 'zoneChest',
            points: _trap(0.325, 0.675, 0.270, 0.730, 0.155, 0.580))
      else
        BodyZone(id: 'back', labelKey: 'zoneBack',
            points: _trap(0.325, 0.675, 0.270, 0.730, 0.155, 0.580)),
      // Bras : membre entier (haut du bras, avant-bras, main). Commence SOUS
      // les épaules, et suit le vide réel entre le bras et le tronc.
      BodyZone(id: 'arm_l', labelKey: 'zoneArms',
          points: _trap(0.115, 0.280, 0.030, 0.175, 0.320, 0.580)),
      BodyZone(id: 'arm_r', labelKey: 'zoneArms',
          points: _trap(0.720, 0.885, 0.825, 0.970, 0.320, 0.580)),
      // Jambes : les deux membres inférieurs, cuisse à pied.
      BodyZone(id: 'leg_l', labelKey: 'zoneLegs',
          points: _trap(0.259, 0.478, 0.310, 0.415, 0.580, 0.980)),
      BodyZone(id: 'leg_r', labelKey: 'zoneLegs',
          points: _trap(0.522, 0.741, 0.585, 0.690, 0.580, 0.980)),
    ];

/// Zone sous un point normalisé (null si hors du corps).
BodyZone? zoneAt(BodyView view, Offset normalized) {
  // Ordre inverse : les membres sont dessinés après le tronc, donc une zone
  // tardive gagne en cas de chevauchement (épaule / bras).
  for (final z in bodyZones(view).reversed) {
    if (z.containsNormalized(normalized)) return z;
  }
  return null;
}

/// Type de blessure.
///
/// Liste MINIMALE en attendant celle du street medic : la remplacer ici suffit.
class InjuryType {
  const InjuryType(this.id, this.labelKey, this.color);
  final String id;
  final String labelKey;
  final Color color;
}

const List<InjuryType> kInjuryTypes = [
  InjuryType('wound', 'injuryWound', Color(0xFFD32F2F)),
  InjuryType('fracture', 'injuryFracture', Color(0xFF1976D2)),
  InjuryType('burn', 'injuryBurn', Color(0xFFE64A19)),
  InjuryType('other', 'injuryOther', Color(0xFF616161)),
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

  Injury copyWith({String? typeId}) =>
      Injury(zoneId: zoneId, typeId: typeId ?? this.typeId);
}
