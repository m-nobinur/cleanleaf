import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleanleaf/core/platform/clvision.dart';
import 'package:cleanleaf/main_native_smoke.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

const _heatmapLength = modelHeatmapSize * modelHeatmapSize * 4;

Float32List _run(Float32List input) => using((arena) {
  final inputPtr = arena<Float>(input.length)
    ..asTypedList(input.length).setAll(0, input);
  final out = arena<Float>(_heatmapLength);
  expect(clvModelRun(inputPtr, out), ClvStatus.ok);
  return Float32List.fromList(out.asTypedList(_heatmapLength));
});

// T-018 parity inputs: 256x256 BGR bytes of its synthetic renders s030, s065.
Float32List _parityInput(String name) => Float32List.fromList([
  for (final b in File(
    'test/fixtures/detection/parity_${name}_256.bgr',
  ).readAsBytesSync())
    b / 255,
]);

/// Heatmap cell of the channel maximum, scaled to 256-px input coordinates.
(double, double) _argmax(Float32List heatmaps, int channel) {
  var best = -1.0;
  var at = 0;
  for (var i = 0; i < modelHeatmapSize * modelHeatmapSize; i++) {
    if (heatmaps[i * 4 + channel] > best) {
      best = heatmaps[i * 4 + channel];
      at = i;
    }
  }
  return ((at % modelHeatmapSize) * 2.0, (at ~/ modelHeatmapSize) * 2.0);
}

void main() {
  setUpAll(() {
    final model = File(docAlignerAsset).readAsBytesSync();
    using((arena) {
      final bytes = arena<Uint8>(model.length)
        ..asTypedList(model.length).setAll(0, model);
      expect(clvModelLoad(bytes, model.length), ClvStatus.ok);
    });
    expect(clvModelLoaded(), 1);
  });

  test('reproduces T-018 device peaks and corners on the parity page', () {
    final heatmaps = _run(_parityInput('doc'));
    final peaks = heatmapPeaks(heatmaps);
    const devicePeaks = [0.9432, 0.9213, 0.9477, 0.9393];
    const deviceCorners = [
      (82.67, 24.56),
      (178.96, 25.36),
      (192.5, 240.5),
      (105.36, 244.04),
    ];
    for (var k = 0; k < 4; k++) {
      expect(peaks[k], closeTo(devicePeaks[k], 0.002), reason: 'peak $k');
      final (x, y) = _argmax(heatmaps, k);
      expect(x, closeTo(deviceCorners[k].$1, 4), reason: 'corner $k x');
      expect(y, closeTo(deviceCorners[k].$2, 4), reason: 'corner $k y');
    }
  });

  test('finds no page on the parity no-document frame', () {
    final peaks = heatmapPeaks(_run(_parityInput('nodoc')));
    expect(peaks.reduce((a, b) => a < b ? a : b), lessThan(0.3));
  });

  test('finds the smoke page the device run uses', () {
    final heatmaps = _run(smokePage());
    final peaks = heatmapPeaks(heatmaps);
    // ignore: avoid_print
    print('smoke peaks ${peaks.map((p) => p.toStringAsFixed(4)).join(',')}');
    for (var k = 0; k < 4; k++) {
      expect(peaks[k], greaterThan(0.3), reason: 'peak $k');
      final (x, y) = _argmax(heatmaps, k);
      expect(x, closeTo(smokeCorners[k].$1, 8), reason: 'corner $k x');
      expect(y, closeTo(smokeCorners[k].$2, 8), reason: 'corner $k y');
    }
  });
}
