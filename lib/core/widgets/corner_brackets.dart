import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

/// The brand motif: four corner strokes (┌ ┐ └ ┘) around [child].
class CornerBrackets extends StatelessWidget {
  const CornerBrackets({
    super.key,
    required this.color,
    this.strokeWidth = 2,
    this.length = 0.28,
    this.child,
  });

  final Color color;
  final double strokeWidth;

  /// Arm length as a fraction of the shorter side.
  final double length;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: CornerBracketsPainter(
      color: color,
      strokeWidth: strokeWidth,
      length: length,
    ),
    child: child,
  );
}

class CornerBracketsPainter extends CustomPainter {
  const CornerBracketsPainter({
    required this.color,
    required this.strokeWidth,
    required this.length,
  });

  final Color color;
  final double strokeWidth;
  final double length;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = (Offset.zero & size).deflate(inset);
    final arm = size.shortestSide * length;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final corners = [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ];
    for (final (corner, dx, dy) in corners) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy + dy * arm)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx + dx * arm, corner.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CornerBracketsPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.length != length;
}

/// The bracket motif in a leaf circle: the app mark on sheet headers.
class BrandBadge extends StatelessWidget {
  const BrandBadge({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size / 4),
      decoration: BoxDecoration(
        color: colors.tileLeaf,
        shape: BoxShape.circle,
        border: Border.all(color: colors.tileLeafEdge),
      ),
      child: CornerBrackets(
        color: colors.leafText,
        length: 0.34,
        child: const SizedBox.expand(),
      ),
    );
  }
}
