import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sélecteur de blessures sur silhouette anatomique.
///
/// **Image** : silhouette humaine asexuée, CC0 (domaine public), rendue par
/// `flutter_svg` depuis `assets/anatomy/body_front.svg` et `body_back.svg`.
///
/// **Zones** : polygones INVISIBLES superposés à l'image. Cette séparation
/// permet d'avoir une belle illustration *et* un hit-testing exact, sans
/// dépendre du découpage interne du SVG (qui compte 7 tracés avec des
/// translations imbriquées — inexploitables directement).
///
/// **Calibrage** : les polygones ne sont pas devinés. Ils sont mesurés sur le
/// rendu réel des SVG (profil de largeur relevé tous les 5 % de hauteur), ce
/// qui garantit que chaque zone tombe bien sur la partie du corps visée.
///
/// **Zoom** : la géométrie vit en coordonnées normalisées (0..1) et ne bouge
/// jamais ; le zoom n'est qu'une transformation de rendu, et les taps sont
/// reconvertis par l'inverse de la matrice. Sans cela la détection se décale
/// dès qu'on zoome.

/// Vue affichée.
enum BodyView { front, back }

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

  /// Identifiant stable, stocké côté serveur (`head`, `arm_l`, ...).
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

/// Polygone rectangulaire (la plupart des zones sont des blocs simples).
List<Offset> _rect(double l, double t, double r, double b) =>
    [Offset(l, t), Offset(r, t), Offset(r, b), Offset(l, b)];

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

/// Coordonnées mesurées sur le rendu réel (voir `/tmp/measure_render.py`).
///
/// Repères de la vue de FACE :
///   y 0.00-0.14 tête | 0.14-0.20 cou | 0.18-0.42 torse
///   0.42-0.56 bassin + mains | 0.56-0.92 jambes | 0.92-1.00 pieds
///   bras : x 0.03-0.22 (gauche écran) et 0.78-0.97, y 0.20-0.56
///
/// Les épaules s'arrêtent AVANT le haut des bras (0.25 vs 0.25) : sans cette
/// séparation, le centre de l'épaule tombait dans le polygone du bras, qui est
/// dessiné par-dessus — l'épaule devenait donc intouchable.
List<BodyZone> _frontZones() => [
      BodyZone(id: 'head', labelKey: 'zoneHead',
          points: _ellipse(0.5, 0.072, 0.076, 0.058)),
      BodyZone(id: 'neck', labelKey: 'zoneNeck',
          points: _rect(0.462, 0.138, 0.538, 0.196)),
      BodyZone(id: 'shoulder_l', labelKey: 'zoneShoulderL',
          points: _trap(0.300, 0.400, 0.215, 0.330, 0.196, 0.250)),
      BodyZone(id: 'shoulder_r', labelKey: 'zoneShoulderR',
          points: _trap(0.600, 0.700, 0.670, 0.785, 0.196, 0.250)),
      BodyZone(id: 'chest', labelKey: 'zoneChest',
          points: _rect(0.330, 0.196, 0.670, 0.400)),
      BodyZone(id: 'abdomen', labelKey: 'zoneAbdomen',
          points: _rect(0.330, 0.400, 0.670, 0.560)),
      BodyZone(id: 'arm_l', labelKey: 'zoneArmL',
          points: _trap(0.180, 0.330, 0.100, 0.200, 0.252, 0.378)),
      BodyZone(id: 'arm_r', labelKey: 'zoneArmR',
          points: _trap(0.670, 0.820, 0.800, 0.900, 0.252, 0.378)),
      BodyZone(id: 'forearm_l', labelKey: 'zoneForearmL',
          points: _trap(0.100, 0.200, 0.060, 0.155, 0.378, 0.490)),
      BodyZone(id: 'forearm_r', labelKey: 'zoneForearmR',
          points: _trap(0.800, 0.900, 0.845, 0.940, 0.378, 0.490)),
      BodyZone(id: 'hand_l', labelKey: 'zoneHandL',
          points: _ellipse(0.090, 0.525, 0.055, 0.040)),
      BodyZone(id: 'hand_r', labelKey: 'zoneHandR',
          points: _ellipse(0.910, 0.525, 0.055, 0.040)),
      BodyZone(id: 'thigh_l', labelKey: 'zoneThighL',
          points: _trap(0.300, 0.490, 0.295, 0.480, 0.560, 0.720)),
      BodyZone(id: 'thigh_r', labelKey: 'zoneThighR',
          points: _trap(0.510, 0.700, 0.520, 0.705, 0.560, 0.720)),
      BodyZone(id: 'shin_l', labelKey: 'zoneShinL',
          points: _trap(0.295, 0.480, 0.320, 0.460, 0.720, 0.920)),
      BodyZone(id: 'shin_r', labelKey: 'zoneShinR',
          points: _trap(0.520, 0.705, 0.540, 0.680, 0.720, 0.920)),
      BodyZone(id: 'foot_l', labelKey: 'zoneFootL',
          points: _rect(0.310, 0.920, 0.470, 0.985)),
      BodyZone(id: 'foot_r', labelKey: 'zoneFootR',
          points: _rect(0.530, 0.920, 0.690, 0.985)),
    ];

/// Repères de la vue de DOS (mêmes proportions, tronc redécoupé).
List<BodyZone> _backZones() => [
      BodyZone(id: 'head', labelKey: 'zoneHead',
          points: _ellipse(0.5, 0.072, 0.076, 0.058)),
      BodyZone(id: 'nape', labelKey: 'zoneNape',
          points: _rect(0.462, 0.138, 0.538, 0.196)),
      BodyZone(id: 'shoulder_l', labelKey: 'zoneShoulderL',
          points: _trap(0.300, 0.400, 0.215, 0.330, 0.196, 0.250)),
      BodyZone(id: 'shoulder_r', labelKey: 'zoneShoulderR',
          points: _trap(0.600, 0.700, 0.670, 0.785, 0.196, 0.250)),
      BodyZone(id: 'back', labelKey: 'zoneBack',
          points: _rect(0.330, 0.196, 0.670, 0.400)),
      BodyZone(id: 'lower_back', labelKey: 'zoneLowerBack',
          points: _rect(0.330, 0.400, 0.670, 0.560)),
      BodyZone(id: 'arm_l', labelKey: 'zoneArmL',
          points: _trap(0.180, 0.330, 0.100, 0.200, 0.252, 0.378)),
      BodyZone(id: 'arm_r', labelKey: 'zoneArmR',
          points: _trap(0.670, 0.820, 0.800, 0.900, 0.252, 0.378)),
      BodyZone(id: 'forearm_l', labelKey: 'zoneForearmL',
          points: _trap(0.100, 0.200, 0.060, 0.155, 0.378, 0.490)),
      BodyZone(id: 'forearm_r', labelKey: 'zoneForearmR',
          points: _trap(0.800, 0.900, 0.845, 0.940, 0.378, 0.490)),
      BodyZone(id: 'hand_l', labelKey: 'zoneHandL',
          points: _ellipse(0.090, 0.525, 0.055, 0.040)),
      BodyZone(id: 'hand_r', labelKey: 'zoneHandR',
          points: _ellipse(0.910, 0.525, 0.055, 0.040)),
      BodyZone(id: 'thigh_l', labelKey: 'zoneThighL',
          points: _trap(0.300, 0.490, 0.295, 0.480, 0.560, 0.720)),
      BodyZone(id: 'thigh_r', labelKey: 'zoneThighR',
          points: _trap(0.510, 0.700, 0.520, 0.705, 0.560, 0.720)),
      BodyZone(id: 'shin_l', labelKey: 'zoneShinL',
          points: _trap(0.295, 0.480, 0.320, 0.460, 0.720, 0.920)),
      BodyZone(id: 'shin_r', labelKey: 'zoneShinR',
          points: _trap(0.520, 0.705, 0.540, 0.680, 0.720, 0.920)),
      BodyZone(id: 'foot_l', labelKey: 'zoneFootL',
          points: _rect(0.310, 0.920, 0.470, 0.985)),
      BodyZone(id: 'foot_r', labelKey: 'zoneFootR',
          points: _rect(0.530, 0.920, 0.690, 0.985)),
    ];

/// Toutes les zones d'une vue.
List<BodyZone> bodyZones(BodyView view) =>
    view == BodyView.front ? _frontZones() : _backZones();

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
