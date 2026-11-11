import 'dart:typed_data';

class StillResult {
  const StillResult({
    required this.decodeMs,
    required this.warpMs,
    required this.enhanceMs,
    required this.encodeMs,
    required this.mean,
    required this.jpeg,
  });

  final double decodeMs;
  final double warpMs;
  final double enhanceMs;
  final double encodeMs;
  final double mean;
  final Uint8List jpeg;
}

/// Orders 4 points TL, TR, BR, BL by coordinate sum and difference.
Float32List orderCorners(List<(double, double)> pts) {
  double sum((double, double) p) => p.$1 + p.$2;
  double diff((double, double) p) => p.$1 - p.$2;
  (double, double) byMin(double Function((double, double)) f) =>
      pts.reduce((a, b) => f(a) <= f(b) ? a : b);
  (double, double) byMax(double Function((double, double)) f) =>
      pts.reduce((a, b) => f(a) >= f(b) ? a : b);
  final ordered = [byMin(sum), byMax(diff), byMax(sum), byMin(diff)];
  return Float32List.fromList([
    for (final p in ordered) ...[p.$1, p.$2],
  ]);
}
