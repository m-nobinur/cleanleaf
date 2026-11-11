import '../../../core/geometry/quad.dart';

// Corner i is QuadCorners.corners[i]; edge i runs from corner i to corner
// i + 1 (top, right, bottom, left), the same order as EdgeAnchors.

Quad quadFromCorners(List<Point> c) =>
    (topLeft: c[0], topRight: c[1], bottomRight: c[2], bottomLeft: c[3]);

double _clamp01(double v) => v.clamp(0.0, 1.0);

Point clampPoint(Point p) => (x: _clamp01(p.x), y: _clamp01(p.y));

Quad moveCorner(Quad quad, int corner, Point to) =>
    quadFromCorners([...quad.corners]..[corner] = clampPoint(to));

/// Translates both ends of [edge] by [delta], limited so the edge keeps its
/// shape instead of skewing when one end hits the image border.
Quad moveEdge(Quad quad, int edge, Point delta) {
  final c = [...quad.corners];
  final a = c[edge], b = c[(edge + 1) % 4];
  double limit(double d, double p, double q) =>
      d.clamp(-(p < q ? p : q), 1 - (p > q ? p : q));
  final dx = limit(delta.x, a.x, b.x), dy = limit(delta.y, a.y, b.y);
  c[edge] = (x: a.x + dx, y: a.y + dy);
  c[(edge + 1) % 4] = (x: b.x + dx, y: b.y + dy);
  return quadFromCorners(c);
}

Point edgeMidpoint(Quad quad, int edge) {
  final c = quad.corners;
  final a = c[edge], b = c[(edge + 1) % 4];
  return (x: (a.x + b.x) / 2, y: (a.y + b.y) / 2);
}

/// Strictly convex with clockwise corners (y down). A mirrored but convex quad
/// is rejected because the warp would flip the page.
bool isValidQuad(Quad quad, {double epsilon = 1e-6}) {
  final c = quad.corners;
  for (var i = 0; i < 4; i++) {
    final a = c[i], b = c[(i + 1) % 4], d = c[(i + 2) % 4];
    final cross = (b.x - a.x) * (d.y - b.y) - (b.y - a.y) * (d.x - b.x);
    if (cross <= epsilon) return false;
  }
  return true;
}
