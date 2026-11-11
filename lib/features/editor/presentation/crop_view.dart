import 'dart:math' as math;
import 'dart:ui';

import '../../../core/geometry/quad.dart';

/// How far the editor zooms in past fitting the whole photo.
const maxZoom = 4.0;

/// The normalized bounding box of [quad].
Rect quadBounds(Quad quad) {
  final xs = [for (final p in quad.corners) p.x];
  final ys = [for (final p in quad.corners) p.y];
  return Rect.fromLTRB(
    xs.reduce(math.min),
    ys.reduce(math.min),
    xs.reduce(math.max),
    ys.reduce(math.max),
  );
}

/// Where to draw an [image]-sized photo so that [focus] (normalized, grown by
/// [margin] of its size per side) fills [area]; never smaller than the whole
/// photo fitted, never more than [maxZoom] times that.
Rect fitView(
  Size image,
  Rect area, {
  Rect focus = const Rect.fromLTWH(0, 0, 1, 1),
  double margin = 0,
}) {
  final grown = Rect.fromLTRB(
    math.max(0, focus.left - margin * focus.width),
    math.max(0, focus.top - margin * focus.height),
    math.min(1, focus.right + margin * focus.width),
    math.min(1, focus.bottom + margin * focus.height),
  );
  final whole = _fitScale(image, area);
  final scale = math
      .min(
        area.width / math.max(grown.width * image.width, 1e-9),
        area.height / math.max(grown.height * image.height, 1e-9),
      )
      .clamp(whole, whole * maxZoom);
  final size = image * scale;
  final center = grown.center;
  return clampView(
    Rect.fromLTWH(
      area.center.dx - center.dx * size.width,
      area.center.dy - center.dy * size.height,
      size.width,
      size.height,
    ),
    area,
  );
}

/// [view] scaled by [scale] about [from] (start focal point), then moved so
/// that point sits at [to]; zoom stays within [fitView]'s limits.
Rect zoomView(
  Rect view,
  Size image,
  Rect area, {
  required double scale,
  required Offset from,
  required Offset to,
}) {
  final whole = _fitScale(image, area);
  final width = (view.width * scale).clamp(
    image.width * whole,
    image.width * whole * maxZoom,
  );
  final s = width / view.width;
  return clampView(
    Rect.fromLTWH(
      to.dx - (from.dx - view.left) * s,
      to.dy - (from.dy - view.top) * s,
      view.width * s,
      view.height * s,
    ),
    area,
  );
}

/// Centres an axis that fits inside [area]; otherwise keeps [area] covered.
Rect clampView(Rect view, Rect area) {
  double axis(double start, double size, double areaStart, double areaSize) =>
      size <= areaSize
      ? areaStart + (areaSize - size) / 2
      : start.clamp(areaStart + areaSize - size, areaStart);
  return Rect.fromLTWH(
    axis(view.left, view.width, area.left, area.width),
    axis(view.top, view.height, area.top, area.height),
    view.width,
    view.height,
  );
}

/// [view] moved just enough to bring [point] back inside [area].
Rect revealView(Rect view, Rect area, Offset point) {
  double push(double p, double lo, double hi) =>
      p < lo ? lo - p : (p > hi ? hi - p : 0);
  return clampView(
    view.shift(
      Offset(
        push(point.dx, area.left, area.right),
        push(point.dy, area.top, area.bottom),
      ),
    ),
    area,
  );
}

double _fitScale(Size image, Rect area) =>
    math.min(area.width / image.width, area.height / image.height);
