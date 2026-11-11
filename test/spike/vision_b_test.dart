import 'dart:typed_data';

import 'package:cleanleaf/spike/vision/pipeline_b.dart';
import 'package:flutter_test/flutter_test.dart';

import 'synthetic.dart';

void main() {
  test('B detects the synthetic page in a strided 480x640 frame', () {
    const w = 480, h = 640, stride = 544;
    final corners = detectFrameB(
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

  test('B warps and flattens a synthetic still', () {
    const w = 900, h = 1200;
    final jpeg = encodeBgrB(syntheticBgr(w, h), w, h);
    final corners = Float32List.fromList(expectedCorners(w, h));
    final r = stillB(jpeg, corners, 700, 990);
    expect(r.jpeg.length, greaterThan(10000));
    expect(r.mean, greaterThan(170));
  });
}
