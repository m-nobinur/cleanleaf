import 'dart:typed_data';

import 'package:cleanleaf/spike/vision/pipeline_a.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'synthetic.dart';

void main() {
  test('A detects the synthetic page in a strided 480x640 frame', () {
    const w = 480, h = 640, stride = 544;
    final corners = detectFrameA(
      syntheticGray(w, h, stride: stride),
      w,
      h,
      stride,
    );
    expect(corners, isNotNull);
    final expected = expectedCorners(w, h);
    for (var i = 0; i < 8; i++) {
      expect(corners![i], closeTo(expected[i], cornerTolerance(w, h)));
    }
  });

  test('A warps and flattens a synthetic still', () {
    const w = 900, h = 1200;
    final src = cv.Mat.fromList(h, w, cv.MatType.CV_8UC3, syntheticBgr(w, h));
    final (_, jpeg) = cv.imencode('.jpg', src);
    final corners = expectedCorners(w, h);
    final sw = Stopwatch()..start();
    final r = stillA(jpeg, corners.toFloat32List(), 700, 990);
    expect(r.jpeg.length, greaterThan(10000));
    // Division flattens the shadowed paper towards white.
    expect(r.mean, greaterThan(170));
    printOnFailure('A still ${sw.elapsedMilliseconds} ms, mean ${r.mean}');
  });
}

extension on List<double> {
  Float32List toFloat32List() => Float32List.fromList(this);
}
