import 'package:flutter/material.dart';

import 'body_map.dart';

/// Silhouette interactive avec zoom sur la zone touchée.
///
/// Le zoom n'est qu'une transformation de rendu : la géométrie des zones vit
/// en coordonnées normalisées (0..1) et les taps sont reconvertis par l'inverse
/// de la matrice courante. La détection reste donc exacte à toute échelle.
class BodyMapView extends StatefulWidget {
  const BodyMapView({
    super.key,
    required this.view,
    required this.injuries,
    required this.onZoneTapped,
    this.selectedTypeId,
    this.zoomEnabled = true,
  });

  final BodyView view;
  final List<Injury> injuries;
  final void Function(BodyZone zone) onZoneTapped;
  final String? selectedTypeId;
  final bool zoomEnabled;

  @override
  State<BodyMapView> createState() => BodyMapViewState();
}

class BodyMapViewState extends State<BodyMapView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Animation<double> _anim = const AlwaysStoppedAnimation(1.0);
  Offset _focus = const Offset(0.5, 0.5);
  bool _zoomed = false;

  static const double _maxScale = 3.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Revenir à la vue d'ensemble.
  void reset() {
    if (!_zoomed) return;
    _zoomed = false;
    _anim = Tween<double>(begin: _anim.value, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward(from: 0);
    setState(() {});
  }

  /// Zoome sur une zone : le cadre s'ajuste à son emprise, avec une marge.
  void zoomOn(BodyZone zone) {
    if (!widget.zoomEnabled) return;
    final b = zone.normalizedBounds();
    // Centre sur la zone ; le facteur dépend de sa taille (une tête demande
    // plus de zoom qu'un buste).
    final span = (b.width > b.height ? b.width : b.height).clamp(0.05, 1.0);
    final target = (_maxScale * (0.30 / span)).clamp(1.6, _maxScale);
    _focus = b.center;
    _zoomed = true;
    _anim = Tween<double>(begin: _anim.value, end: target).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward(from: 0);
    setState(() {});
  }

  bool get isZoomed => _zoomed;

  /// Convertit un point écran en coordonnées normalisées.
  Offset _toNormalized(Offset local, Size size) {
    final s = _anim.value;
    final center = Offset(size.width * _focus.dx, size.height * _focus.dy);
    final origin = center - (center - Offset.zero) * s;
    final nx = (local.dx - origin.dx) / (size.width * s);
    final ny = (local.dy - origin.dy) / (size.height * s);
    return Offset(nx, ny);
  }

  void _handleTap(Offset local, Size size) {
    final n = _toNormalized(local, size);
    final zone = zoneAt(widget.view, n);
    if (zone == null) {
      // Tap hors du corps : on dézoome, geste naturel pour « annuler ».
      reset();
      return;
    }
    widget.onZoneTapped(zone);
    if (widget.zoomEnabled) zoomOn(zone);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d.localPosition, size),
          child: AnimatedBuilder(
            animation: _anim,
            builder: (ctx2, _) => CustomPaint(
              size: size,
              painter: _BodyPainter(
                view: widget.view,
                injuries: widget.injuries,
                scale: _anim.value,
                focus: _focus,
                onSurface: Theme.of(ctx2).colorScheme.surface,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dessine la silhouette : zones non marquées, puis zones marquées.
class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.view,
    required this.injuries,
    required this.scale,
    required this.focus,
    required this.onSurface,
  });

  final BodyView view;
  final List<Injury> injuries;
  final double scale;
  final Offset focus;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Zoom centré sur la zone : on translate le foyer au centre puis on scale.
    final center = Offset(size.width * focus.dx, size.height * focus.dy);
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    final marked = <String, String>{
      for (final i in injuries) i.zoneId: i.typeId,
    };

    // 1. Base : toutes les zones en gris translucide (silhouette asexuée).
    final base = Paint()
      ..style = PaintingStyle.fill
      ..color = onSurface.withValues(alpha: 0.16);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = onSurface.withValues(alpha: 0.35);

    for (final z in bodyZones(view)) {
      if (marked.containsKey(z.id)) continue; // dessinée après, colorée
      final path = z.toPath(size);
      canvas.drawPath(path, base);
      canvas.drawPath(path, edge);
    }

    // 2. Zones blessées : couleur du type, opacité soutenue.
    for (final z in bodyZones(view)) {
      final typeId = marked[z.id];
      if (typeId == null) continue;
      final type = kInjuryTypes.firstWhere(
        (t) => t.id == typeId,
        orElse: () => kInjuryTypes.last,
      );
      final path = z.toPath(size);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = type.color.withValues(alpha: 0.55),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = type.color,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) =>
      old.view != view ||
      old.scale != scale ||
      old.focus != focus ||
      old.injuries.length != injuries.length ||
      !_sameInjuries(old.injuries, injuries);

  static bool _sameInjuries(List<Injury> a, List<Injury> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].zoneId != b[i].zoneId || a[i].typeId != b[i].typeId) {
        return false;
      }
    }
    return true;
  }
}
