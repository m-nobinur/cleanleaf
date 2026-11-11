import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/core/platform/clvision.dart';
import 'package:cleanleaf/main_detect_bench.dart';
import 'package:cleanleaf/main_render_bench.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Result = ({int status, List<double> corners, double confidence});

_Result _detectImage(Uint8List encoded) => using((arena) {
  final input = arena<Uint8>(encoded.length)
    ..asTypedList(encoded.length).setAll(0, encoded);
  return _read(arena, (c, k) => clvDetectImage(input, encoded.length, c, k));
});

_Result _detectFrame(Arena arena, Pointer<ClvYuvFrame> frame) =>
    _read(arena, (c, k) => clvDetectFrame(frame, c, k));

_Result _read(
  Arena arena,
  int Function(Pointer<Float> corners, Pointer<Float> confidence) detect,
) {
  final corners = arena<Float>(8);
  final confidence = arena<Float>();
  final status = detect(corners, confidence);
  return (
    status: status,
    corners: List.of(corners.asTypedList(8)),
    confidence: confidence.value,
  );
}

List<double> _flat(Quad q) => [
  for (final c in q.corners) ...[c.x, c.y],
];

/// Largest corner distance in pixels of a [width]x[height] image.
double _maxError(List<double> a, List<double> b, int width, int height) {
  var worst = 0.0;
  for (var i = 0; i < 8; i += 2) {
    final dx = (a[i] - b[i]) * width, dy = (a[i + 1] - b[i + 1]) * height;
    worst = math.max(worst, math.sqrt(dx * dx + dy * dy));
  }
  return worst;
}

// Off-centre, so a wrong frame rotation can't land on it.
const _page = (
  topLeft: (x: 0.10, y: 0.08),
  topRight: (x: 0.66, y: 0.14),
  bottomRight: (x: 0.62, y: 0.70),
  bottomLeft: (x: 0.12, y: 0.64),
);

/// A 0.44x0.6 page turned [degrees] clockwise about the centre of a 640x480 frame.
Quad _turnedPage(double degrees) {
  final a = degrees * math.pi / 180;
  Point turn(double x, double y) {
    final px = (x - 0.5) * 640, py = (y - 0.5) * 480;
    return (
      x: 0.5 + (px * math.cos(a) - py * math.sin(a)) / 640,
      y: 0.5 + (px * math.sin(a) + py * math.cos(a)) / 480,
    );
  }

  return (
    topLeft: turn(0.28, 0.2),
    topRight: turn(0.72, 0.2),
    bottomRight: turn(0.72, 0.8),
    bottomLeft: turn(0.28, 0.8),
  );
}

void main() {
  setUpAll(() {
    final model = File(docAlignerAsset).readAsBytesSync();
    using((arena) {
      final bytes = arena<Uint8>(model.length)
        ..asTypedList(model.length).setAll(0, model);
      expect(clvModelLoad(bytes, model.length), ClvStatus.ok);
    });
  });

  // T-007's hit rule: every corner within 2% of the diagonal (16 px at 640x480).
  const tolerance = 16.0;

  group('still', () {
    test('finds an off-centre page, clockwise from the top-left', () {
      final r = _detectImage(syntheticPageBmp(640, 480, quad: _page));
      expect(r.status, ClvStatus.ok);
      expect(r.confidence, greaterThan(0.3));
      expect(_maxError(r.corners, _flat(_page), 640, 480), lessThan(tolerance));
    });

    test('finds a page turned 25 degrees', () {
      final page = _turnedPage(25);
      final r = _detectImage(syntheticPageBmp(640, 480, quad: page));
      expect(r.status, ClvStatus.ok);
      expect(_maxError(r.corners, _flat(page), 640, 480), lessThan(tolerance));
    });

    test('a page partly out of frame gives no page or in-frame corners', () {
      const page = (
        topLeft: (x: -0.25, y: 0.1),
        topRight: (x: 0.6, y: 0.15),
        bottomRight: (x: 0.55, y: 1.3),
        bottomLeft: (x: -0.2, y: 1.25),
      );
      final r = _detectImage(syntheticPageBmp(640, 480, quad: page));
      expect(r.status, anyOf(ClvStatus.ok, ClvStatus.noQuad));
      if (r.status == ClvStatus.ok) {
        expect(r.corners, everyElement(inInclusiveRange(0, 1)));
      }
    });

    test('an empty desk has no page', () {
      const offFrame = (
        topLeft: (x: 2.0, y: 2.0),
        topRight: (x: 3.0, y: 2.0),
        bottomRight: (x: 3.0, y: 3.0),
        bottomLeft: (x: 2.0, y: 3.0),
      );
      final r = _detectImage(syntheticPageBmp(640, 480, quad: offFrame));
      expect(r.status, ClvStatus.noQuad);
      expect(r.confidence, lessThan(0.3));
    });

    test('rejects missing or undecodable input', () {
      expect(
        _detectImage(Uint8List.fromList([1, 2, 3])).status,
        ClvStatus.decodeFailed,
      );
      using((arena) {
        final out = arena<Float>(9);
        expect(
          clvDetectImage(nullptr, 10, out, out + 8),
          ClvStatus.invalidArgument,
        );
      });
    });
  });

  group('frame', () {
    final bmp = syntheticPageBmp(480, 640, quad: _page);

    test('matches the still for every rotation and chroma layout', () {
      final still = _detectImage(bmp);
      expect(still.status, ClvStatus.ok);
      for (final rotation in [0, 90, 180, 270]) {
        for (final interleaved in [true, false]) {
          using((arena) {
            final frame = yuvFrameFromBmp(
              arena,
              bmp,
              480,
              640,
              rotation: rotation,
              interleaved: interleaved,
              padding: 24,
            );
            final r = _detectFrame(arena, frame);
            final what = 'rotation $rotation interleaved $interleaved';
            expect(r.status, ClvStatus.ok, reason: what);
            expect(
              _maxError(r.corners, still.corners, 480, 640),
              lessThan(2),
              reason: what,
            );
            expect(r.confidence, closeTo(still.confidence, 0.02), reason: what);
          });
        }
      }
    });

    test('a wrong rotation moves the corners', () {
      final still = _detectImage(bmp);
      using((arena) {
        final frame = yuvFrameFromBmp(arena, bmp, 480, 640, rotation: 90);
        frame.ref.rotationDegrees = 270;
        final r = _detectFrame(arena, frame);
        if (r.status == ClvStatus.ok) {
          expect(
            _maxError(r.corners, still.corners, 480, 640),
            greaterThan(100),
          );
        }
      });
    });

    test('rejects bad geometry', () {
      using((arena) {
        final out = arena<Float>(9);
        Pointer<ClvYuvFrame> frame() => yuvFrameFromBmp(arena, bmp, 480, 640);
        int detect(Pointer<ClvYuvFrame> f) => clvDetectFrame(f, out, out + 8);
        expect(detect(nullptr), ClvStatus.invalidArgument);
        expect(
          detect(frame()..ref.rotationDegrees = 45),
          ClvStatus.invalidArgument,
        );
        expect(
          detect(frame()..ref.yRowStride = 100),
          ClvStatus.invalidArgument,
        );
        expect(detect(frame()..ref.u = nullptr), ClvStatus.invalidArgument);
      });
    });
  });
}
