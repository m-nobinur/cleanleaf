import 'dart:math' as math;
import 'dart:typed_data';

/// Page corners TL, TR, BR, BL as fractions of width and height.
const pageQuad = [(0.14, 0.13), (0.87, 0.095), (0.93, 0.89), (0.10, 0.925)];

bool _inside(double x, double y, int w, int h) {
  for (var i = 0; i < 4; i++) {
    final (ax, ay) = pageQuad[i];
    final (bx, by) = pageQuad[(i + 1) % 4];
    final cross =
        (bx * w - ax * w) * (y - ay * h) - (by * h - ay * h) * (x - ax * w);
    if (cross < 0) return false;
  }
  return true;
}

/// Low-contrast grain (no edges), strong blobs in the margins away from the
/// page (extra contours), paper with text-like bars, left-to-right shadow.
/// Returns a luminance value and whether the pixel is on paper.
(int, bool) _pixel(int x, int y, int w, int h) {
  final shade = 0.65 + 0.35 * x / w;
  if (!_inside(x.toDouble(), y.toDouble(), w, h)) {
    final margin = x < 0.08 * w || x > 0.95 * w || y < 0.07 * h || y > 0.95 * h;
    final blob = margin && ((x ~/ 12) + (y ~/ 12) * 7) % 5 == 0;
    final grain = ((x * 7919 + y * 104729) ^ (x * y)) & 7;
    return (((blob ? 200 : 90 + grain) * shade).round(), false);
  }
  final line = (y * 70 ~/ h).isEven && ((x * 23 ~/ w) % 5 != 0);
  return (((line ? 50 : 235) * shade).round(), true);
}

Uint8List syntheticGray(int w, int h, {int? stride}) {
  final s = stride ?? w;
  final out = Uint8List(s * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out[y * s + x] = _pixel(x, y, w, h).$1;
    }
  }
  return out;
}

/// Packed BGR, paper slightly warm, background brown.
Uint8List syntheticBgr(int w, int h) {
  final out = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final (v, paper) = _pixel(x, y, w, h);
      final i = (y * w + x) * 3;
      out[i] = paper ? (v * 0.95).round() : (v * 0.6).round();
      out[i + 1] = paper ? v : (v * 0.8).round();
      out[i + 2] = v;
    }
  }
  return out;
}

List<double> expectedCorners(int w, int h) => [
  for (final (x, y) in pageQuad) ...[x * w, y * h],
];

/// T-007 rule: every corner within 2% of the image diagonal.
double cornerTolerance(int w, int h) => 0.02 * math.sqrt(w * w + h * h);
