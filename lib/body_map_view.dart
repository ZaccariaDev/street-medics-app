import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'body_map.dart';

/// Silhouette anatomique interactive, avec zoom sur la zone touchée.
///
/// Superposition de trois couches :
///   1. l'image SVG (silhouette CC0), teintée et semi-transparente ;
///   2. les zones cliquables, invisibles (polygones calibrés sur le rendu) ;
///   3. les blessures, en couleur pleine — elles ressortent nettement sur la
///      silhouette translucide, comme la lésion mise en évidence sur les
///      illustrations médicales de référence.
///
/// Le zoom n'est qu'une transformation de rendu : la géométrie reste en
/// coordonnées normalisées et les taps sont reconvertis par l'inverse de la
/// matrice, donc la détection reste exacte à toute échelle.
class BodyMapView extends StatefulWidget {
  const BodyMapView({
    super.key,
    required this.view,
    required this.injuries,
    required this.onZoneTapped,
    this.zoomEnabled = true,
    this.showHints = false,
  });

  final BodyView view;
  final List<Injury> injuries;
  final void Function(BodyZone zone) onZoneTapped;
  final bool zoomEnabled;

  /// Met brièvement en évidence la zone touchée (retour visuel).
  final bool showHints;

  @override
  State<BodyMapView> createState() => BodyMapViewState();
}

class BodyMapViewState extends State<BodyMapView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Animation<double> _anim = const AlwaysStoppedAnimation(1.0);
  Offset _focus = const Offset(0.5, 0.5);
  bool _zoomed = false;
  String? _flashZone;

  /// Facteur de zoom au debut du pincement (le geste est relatif a ce point).
  double _pinchStart = 1.0;

  static const double _maxScale = 3.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _zoomResetTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  bool get isZoomed => _zoomed;

  /// Facteur de zoom courant — expose pour les tests de gestes.
  @visibleForTesting
  double get debugScale => _anim.value;

  /// Retour à la vue d'ensemble.
  void reset() {
    _cancelAutoReset();
    if (!_zoomed) return;
    _zoomed = false;
    _anim = Tween<double>(begin: _anim.value, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward(from: 0);
    setState(() {});
  }

  /// Annule le dezoom automatique (pendant un pincement, l'utilisateur pilote).
  void _cancelAutoReset() {
    _zoomResetTimer?.cancel();
    _zoomResetTimer = null;
  }

  /// Zoome sur une zone ; le facteur dépend de sa taille (une tête demande
  /// plus de grossissement qu'un buste).
  void zoomOn(BodyZone zone) {
    if (!widget.zoomEnabled) return;
    final b = zone.normalizedBounds();
    final span = (b.width > b.height ? b.width : b.height).clamp(0.04, 1.0);
    final target = (_maxScale * (0.26 / span)).clamp(1.5, _maxScale);
    _focus = b.center;
    _zoomed = true;
    _anim = Tween<double>(begin: _anim.value, end: target)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward(from: 0);
    setState(() {});
  }

  /// Zoome sur un point précis (double-tap) : le point touche devient le
  /// centre de la vue. `scale` est le facteur visé.
  void _zoomAt(Offset local, Size size, double scale) {
    if (!widget.zoomEnabled) return;
    _cancelAutoReset();
    final s = _anim.value;
    // Le point touche, ramene en coordonnees normalisees AVANT zoom.
    final c = Offset(size.width * _focus.dx, size.height * _focus.dy);
    final origin = c - c * s;
    _focus = Offset(
      ((local.dx - origin.dx) / (size.width * s)).clamp(0.0, 1.0),
      ((local.dy - origin.dy) / (size.height * s)).clamp(0.0, 1.0),
    );
    _zoomed = true;
    _anim = Tween<double>(begin: _anim.value, end: scale.clamp(1.0, _maxScale))
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward(from: 0);
    setState(() {});
  }

  /// Applique un pincement : le facteur suit l'ecartement des doigts, et le
  /// foyer suit leur milieu. Le zoom est borne.
  void _applyPinch(ScaleUpdateDetails d, Size size) {
    if (!widget.zoomEnabled) return;
    final target = (_pinchStart * d.scale).clamp(1.0, _maxScale);
    // Le foyer : on part du foyer du pincement, dans l'espace normalise.
    final f = d.focalPoint;
    _focus = Offset(
      (f.dx / size.width).clamp(0.0, 1.0),
      (f.dy / size.height).clamp(0.0, 1.0),
    );
    _zoomed = target > 1.02;
    _anim = AlwaysStoppedAnimation(target);
    setState(() {});
  }

  /// Convertit un point écran en coordonnées normalisées.
  Offset _toNormalized(Offset local, Size size) {
    final s = _anim.value;
    final c = Offset(size.width * _focus.dx, size.height * _focus.dy);
    final origin = c - c * s;
    return Offset((local.dx - origin.dx) / (size.width * s),
        (local.dy - origin.dy) / (size.height * s));
  }

  void _handleTap(Offset local, Size size) {
    final zone = zoneAt(widget.view, _toNormalized(local, size));
    if (zone == null) {
      reset(); // tap hors du corps = annuler le zoom
      return;
    }
    setState(() => _flashZone = zone.id);
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _flashZone = null);
    });
    widget.onZoneTapped(zone);
    if (!widget.zoomEnabled) return;
    // Un appui ZOOME sur la zone, puis on revient tout seul a l'ensemble.
    //
    // Le retour est differe par un Timer : si on appelait `reset()` juste
    // apres `zoomOn()`, `reset()` annulerait ce Timer (il commence par
    // `_cancelAutoReset()`), et le dezoom automatique ne se produirait jamais.
    zoomOn(zone);
    _zoomResetTimer?.cancel();
    _zoomResetTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) reset();
    });
  }

  Timer? _zoomResetTimer;

  @override
  Widget build(BuildContext context) {
    // La géométrie suit TOUJOURS la silhouette de face : le dos est un calque
    // derrière elle, jamais une vue substituée. Les zones ne bougent donc pas
    // quand on affiche le dos.
    final asset = BodyViewAsset.front;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (ctx, c) {
        // Le SVG garde son ratio : on l'inscrit dans la zone disponible.
        var w = c.maxWidth;
        var h = w / asset.aspect;
        if (h > c.maxHeight) {
          h = c.maxHeight;
          w = h * asset.aspect;
        }
        final size = Size(w, h);
        final origin = Offset((c.maxWidth - w) / 2, (c.maxHeight - h) / 2);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Un tap selectionne une partie du corps. Un DOUBLE tap zoome sur
          // le point touche ; un pincement zoome librement (voir onScale*).
          onTapUp: (d) {
            final local = d.localPosition - origin;
            if (local.dx < 0 || local.dy < 0 ||
                local.dx > size.width || local.dy > size.height) {
              reset();
              return;
            }
            _handleTap(local, size);
          },
          // Pincement (et double-tap, via onDoubleTapDown) : zoom libre.
          // On garde les deux dans le meme GestureDetector pour que Flutter
          // arbitre entre le tap simple et les gestes de zoom.
          onDoubleTapDown: (d) {
            _pinchStart = 1.0;
            _zoomAt(d.localPosition - origin, size, _maxScale * 0.6);
          },
          onDoubleTap: () {},
          onScaleStart: (d) {
            _pinchStart = _anim.value;
            _cancelAutoReset();
          },
          onScaleUpdate: (d) {
            if (d.pointerCount < 2) return; // un doigt = pas un pincement
            _applyPinch(d, size);
          },
          onScaleEnd: (_) {
            if (_anim.value <= 1.02) reset();
          },
          // SizedBox.expand : le widget occupe TOUTE la place offerte, quelle
          // que soit la mise en page du parent.
          //
          // Sans cela, la largeur retenue etait celle de la silhouette ; le
          // parent la recentrait de son cote, et l'offset de centrage etait
          // donc applique DEUX fois — le corps apparaissait decale vers la
          // droite sur le telephone (bug constate a l'ecran).
          //
          // Le centrage se fait ici par Positioned, jamais par translation :
          // la position est ainsi deterministe.
          child: SizedBox.expand(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (ctx2, _) => Stack(
                children: [
                  Positioned(
                    left: origin.dx,
                    top: origin.dy,
                    width: size.width,
                    height: size.height,
                    child: ClipRect(
                      child: Transform(
                        alignment: Alignment.topLeft,
                        transform: _matrix(size),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 1. Calque « dos » : la silhouette de dos reste
                            //    DERRIERE, en retrait (60 % d'opacité). Elle
                            //    n'est affichée que lorsqu'on désigne le dos —
                            //    le bonhomme ne pivote jamais.
                            //
                            //    Teinte volontairement distincte (bleu ardoise,
                            //    pas une couleur de thème) : les contours de
                            //    face et de dos se superposent presque, donc
                            //    sans couleur nettement différente le calque
                            //    resterait invisible derrière la silhouette.
                            if (widget.view == BodyView.back)
                              Opacity(
                                opacity: 0.6,
                                child: SvgPicture.asset(
                                  BodyViewAsset.back.asset,
                                  fit: BoxFit.fill,
                                  colorFilter: const ColorFilter.mode(
                                    Color(0xFF4A6FA5),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            // 2. Silhouette de face, toujours visible.
                            SvgPicture.asset(
                              BodyViewAsset.front.asset,
                              fit: BoxFit.fill,
                              colorFilter: ColorFilter.mode(
                                scheme.onSurface.withValues(alpha: 0.22),
                                BlendMode.srcIn,
                              ),
                            ),
                            // 3. Zones + 4. blessures.
                            CustomPaint(
                              painter: _ZonePainter(
                                view: widget.view,
                                injuries: widget.injuries,
                                flashZone: _flashZone,
                                outline:
                                    scheme.onSurface.withValues(alpha: 0.18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Matrix4 _matrix(Size size) {
    final s = _anim.value;
    final c = Offset(size.width * _focus.dx, size.height * _focus.dy);
    return Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }
}

/// Dessine les blessures et le contour des zones (jamais leur remplissage,
/// sauf pendant le retour visuel du tap).
class _ZonePainter extends CustomPainter {
  _ZonePainter({
    required this.view,
    required this.injuries,
    required this.flashZone,
    required this.outline,
  });

  final BodyView view;
  final List<Injury> injuries;
  final String? flashZone;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final marked = <String, String>{
      for (final i in injuries) i.zoneId: i.typeId,
    };

    // Blessures : remplissage + contour nets.
    for (final z in bodyZones(view)) {
      final typeId = marked[z.id];
      if (typeId == null) continue;
      final type = kInjuryTypes.firstWhere((t) => t.id == typeId,
          orElse: () => kInjuryTypes.last);
      final path = z.toPath(size);
      canvas.drawPath(path,
          Paint()..color = type.color.withValues(alpha: 0.55));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = type.color);
    }

    // Retour visuel du tap.
    if (flashZone != null) {
      final z = bodyZones(view).where((e) => e.id == flashZone).firstOrNull;
      if (z != null) {
        canvas.drawPath(
            z.toPath(size),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = Colors.white.withValues(alpha: 0.9));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ZonePainter old) =>
      old.view != view ||
      old.flashZone != flashZone ||
      old.injuries.length != injuries.length ||
      !_same(old.injuries, injuries);

  static bool _same(List<Injury> a, List<Injury> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].zoneId != b[i].zoneId || a[i].typeId != b[i].typeId) {
        return false;
      }
    }
    return true;
  }
}
