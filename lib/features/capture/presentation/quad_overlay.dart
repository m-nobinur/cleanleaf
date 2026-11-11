import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import '../../../core/geometry/quad.dart';

/// The live page outline: a tinted quad with bracket strokes at its corners.
/// Glides between detections and fades when the page is lost, so a ~15 fps
/// detection stream still reads as smooth.
class QuadOverlay extends StatefulWidget {
  const QuadOverlay({super.key, required this.quad, required this.color});

  /// Normalized to the preview; null hides the outline.
  final Quad? quad;
  final Color color;

  @override
  State<QuadOverlay> createState() => _QuadOverlayState();
}

class _QuadOverlayState extends State<QuadOverlay>
    with TickerProviderStateMixin {
  late final _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late Quad? _from = widget.quad;
  late Quad? _to = widget.quad;

  @override
  void initState() {
    super.initState();
    if (widget.quad != null) _fade.value = 1;
  }

  @override
  void didUpdateWidget(QuadOverlay old) {
    super.didUpdateWidget(old);
    final next = widget.quad;
    if (next == null) {
      _fade.reverse();
      return;
    }
    if (next == old.quad) return;
    // Appear in place rather than sweeping in from a stale position.
    _from = _fade.value == 0 ? next : _current;
    _to = next;
    _glide.forward(from: 0);
    _fade.forward();
  }

  Quad? get _current {
    final from = _from, to = _to;
    if (from == null || to == null) return to;
    return _lerpQuad(from, to, Curves.easeOut.transform(_glide.value));
  }

  @override
  void dispose() {
    _glide.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _QuadPainter(
      quad: () => _current,
      opacity: () => _fade.value,
      color: widget.color,
      repaint: Listenable.merge([_glide, _fade]),
    ),
  );
}

Quad _lerpQuad(Quad a, Quad b, double t) {
  Point p(Point u, Point v) =>
      (x: lerpDouble(u.x, v.x, t)!, y: lerpDouble(u.y, v.y, t)!);
  return (
    topLeft: p(a.topLeft, b.topLeft),
    topRight: p(a.topRight, b.topRight),
    bottomRight: p(a.bottomRight, b.bottomRight),
    bottomLeft: p(a.bottomLeft, b.bottomLeft),
  );
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({
    required this.quad,
    required this.opacity,
    required this.color,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Quad? Function() quad;
  final double Function() opacity;
  final Color color;

  static const _edgeWidth = 2.0;
  static const _bracketWidth = 4.0;
  static const _bracketLength = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad();
    final alpha = opacity();
    if (q == null || alpha == 0) return;
    final points = [
      for (final c in q.corners)
        Offset(c.x, c.y).scale(size.width, size.height),
    ];
    final outline = Path()..addPolygon(points, true);
    canvas
      ..drawPath(
        outline,
        Paint()..color = color.withValues(alpha: 0.14 * alpha),
      )
      ..drawPath(
        outline,
        Paint()
          ..color = color.withValues(alpha: 0.8 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _edgeWidth
          ..strokeJoin = StrokeJoin.round,
      );
    final bracket = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _bracketWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < 4; i++) {
      final corner = points[i];
      Offset toward(Offset other) {
        final edge = other - corner;
        final length = math.min(_bracketLength, edge.distance / 3);
        return edge.distance == 0
            ? corner
            : corner + edge / edge.distance * length;
      }

      final previous = toward(points[(i + 3) % 4]);
      final next = toward(points[(i + 1) % 4]);
      canvas.drawPath(
        Path()
          ..moveTo(previous.dx, previous.dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(next.dx, next.dy),
        bracket,
      );
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) => old.color != color;
}
