import 'dart:math' as math;
import 'dart:ui';

import '../../../core/geometry/quad.dart';

/// Maps between the upright camera frame, normalized to 0..1, and a view the
/// frame covers: scaled to fill, the overflow cropped equally on both sides.
/// Corners and focus points are already upright (D-38), so the texture's
/// quarter turns never enter here.
class PreviewTransform {
  PreviewTransform({required Size frame, required Size view})
    : frameRect = _cover(frame, view);

  /// Where the whole frame lands in view coordinates; it overflows the view.
  final Rect frameRect;

  static Rect _cover(Size frame, Size view) {
    final scale = math.max(
      view.width / frame.width,
      view.height / frame.height,
    );
    return Rect.fromCenter(
      center: view.center(Offset.zero),
      width: frame.width * scale,
      height: frame.height * scale,
    );
  }

  Offset toView(Point p) =>
      frameRect.topLeft + Offset(p.x * frameRect.width, p.y * frameRect.height);

  Point toFrame(Offset o) => (
    x: (o.dx - frameRect.left) / frameRect.width,
    y: (o.dy - frameRect.top) / frameRect.height,
  );
}
