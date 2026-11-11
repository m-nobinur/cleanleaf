import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'core/platform/camera_api.g.dart';
import 'core/platform/clvision.dart';
import 'core/platform/vision_api.g.dart';

// Device smoke test for the native stack: run with -t and read
// `adb logcat -s flutter:I` until `CLBENCH DONE`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _step('version', () async => openCvVersion());
  await _step('jni', VisionHostApi().opencvVersion);
  await _step('camera', () async {
    final caps = await CameraHostApi().capabilities();
    if (caps == null) return 'no back camera';
    return '${caps.sensorWidth}x${caps.sensorHeight} '
        'level=${caps.hardwareLevel.name} torch=${caps.hasTorch} '
        'orientation=${caps.sensorOrientation}';
  });
  await _step('model', _runModel);
  await _step(
    'jni-model',
    () async => 'loaded=${await VisionHostApi().isModelLoaded()}',
  );
  debugPrint('CLBENCH DONE');
  runApp(const SizedBox.shrink());
}

Future<void> _step(String name, Future<String> Function() run) async {
  try {
    debugPrint('CLBENCH $name ${await run()}');
  } catch (e) {
    debugPrint('CLBENCH $name FAILED $e');
  }
}

Future<String> _runModel() async {
  final model = (await rootBundle.load(docAlignerAsset)).buffer.asUint8List();
  return using((arena) {
    final bytes = arena<Uint8>(model.length)
      ..asTypedList(model.length).setAll(0, model);
    final loadStatus = clvModelLoad(bytes, model.length);
    if (loadStatus != ClvStatus.ok) return 'load status=$loadStatus';
    final input = smokePage();
    final inputPtr = arena<Float>(input.length)
      ..asTypedList(input.length).setAll(0, input);
    const outLength = modelHeatmapSize * modelHeatmapSize * 4;
    final out = arena<Float>(outLength);
    final times = <int>[];
    for (var i = 0; i < 6; i++) {
      final watch = Stopwatch()..start();
      final status = clvModelRun(inputPtr, out);
      if (status != ClvStatus.ok) return 'run status=$status';
      times.add(watch.elapsedMicroseconds);
    }
    final warm = (times.skip(1).toList()..sort())[2] / 1000;
    final peaks = heatmapPeaks(out.asTypedList(outLength));
    return 'peaks=${peaks.map((p) => p.toStringAsFixed(4)).join(',')} '
        'ms=${warm.toStringAsFixed(1)} first_ms=${(times.first / 1000).toStringAsFixed(1)}';
  });
}

/// Max of each heatmap channel (TL, TR, BR, BL) of a 128x128x4 NHWC output.
List<double> heatmapPeaks(Float32List heatmaps) {
  final peaks = List.filled(4, 0.0);
  for (var i = 0; i < heatmaps.length; i++) {
    if (heatmaps[i] > peaks[i % 4]) peaks[i % 4] = heatmaps[i];
  }
  return peaks;
}

/// A light page with dark text bars on a dark table, as model input
/// (256x256x3 BGR in 0..1). Corners TL, TR, BR, BL in input pixels: [smokeCorners].
Float32List smokePage() {
  const size = modelInputSize;
  final out = Float32List(size * size * 3);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var v = 0.1;
      if (_insideQuad(x + 0.5, y + 0.5)) {
        final textBar = y % 12 < 3 && x > 95 && x < 165 && y > 70 && y < 190;
        v = textBar ? 0.3 : 0.92;
      }
      out.fillRange((y * size + x) * 3, (y * size + x) * 3 + 3, v);
    }
  }
  return out;
}

const smokeCorners = [
  (70.0, 40.0),
  (190.0, 48.0),
  (198.0, 220.0),
  (62.0, 212.0),
];

bool _insideQuad(double x, double y) {
  for (var i = 0; i < 4; i++) {
    final (ax, ay) = smokeCorners[i];
    final (bx, by) = smokeCorners[(i + 1) % 4];
    if ((bx - ax) * (y - ay) - (by - ay) * (x - ax) < 0) return false;
  }
  return true;
}
