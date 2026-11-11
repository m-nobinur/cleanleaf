import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'core/platform/camera_api.g.dart';
import 'core/platform/clvision.dart';

// Times detection on the device and logs every result for an on-device accuracy
// check. Run with -t: the app creates <external files>/detect-bench/ (a dir adb
// creates is unreadable to the app) and waits up to 3 min for expected.json,
// which must be pushed last after the photos (*.jpg, *.png; big*.jpg are timed
// 5 times) and upright frames (*.bmp, fed as 90-degree NV21 like the phone's
// analysis frames). Read `adb logcat -s flutter:I` until `CLBENCH DONE`; the
// same lines go to detect-bench/results.txt.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final texture = ValueNotifier<int?>(null);
  runApp(
    ValueListenableBuilder(
      valueListenable: texture,
      builder: (_, id, _) =>
          id == null ? const SizedBox.shrink() : Texture(textureId: id),
    ),
  );
  final dir = Directory(
    '${(await getExternalStorageDirectory())!.path}/detect-bench',
  )..createSync();
  final lines = <String>[];
  void log(String line) {
    lines.add(line);
    debugPrint('CLBENCH $line');
  }

  try {
    log('waiting for inputs in ${dir.path}');
    final sentinel = File('${dir.path}/expected.json');
    for (var i = 0; i < 180 && !sentinel.existsSync(); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await runDetectBench(dir, texture, log);
  } catch (e, stack) {
    log('FAILED $e $stack');
  } finally {
    log('DONE');
    File('${dir.path}/results.txt').writeAsStringSync('${lines.join('\n')}\n');
  }
}

Future<void> runDetectBench(
  Directory dir,
  ValueNotifier<int?> texture,
  void Function(String) log,
) async {
  final watch = Stopwatch()..start();
  await loadDocAligner();
  log(
    'load ms=${watch.elapsedMilliseconds} cpus=${Platform.numberOfProcessors}',
  );
  final files = dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  String name(File f) => f.uri.pathSegments.last;
  final images = [
    for (final f in files)
      if (RegExp(r'\.(jpe?g|png)$').hasMatch(name(f))) f,
  ];
  final frames = [
    for (final f in files)
      if (name(f).endsWith('.bmp')) f,
  ];
  log('inputs images=${images.length} frames=${frames.length}');

  final arena = Arena();
  try {
    final yuv = {
      for (final f in frames)
        name(f): _frameFromBmp(arena, f.readAsBytesSync()),
    };
    final out = arena<Float>(9);
    final input = arena<Float>(modelInputSize * modelInputSize * 3);
    final heatmaps = arena<Float>(modelHeatmapSize * modelHeatmapSize * 4);

    void timeDetection(String config) {
      log('$config model ${_times(20, () => clvModelRun(input, heatmaps))}');
      for (final MapEntry(:key, :value) in yuv.entries) {
        final timing = _times(10, () => clvDetectFrame(value, out, out + 8));
        final status = clvDetectFrame(value, out, out + 8);
        log('frame $config $key ${_result(status, out)} $timing');
      }
    }

    for (final fp16 in [0, 1]) {
      final config = fp16 == 1 ? 'fp16' : 'fp32';
      log('$config set=${clvModelSetFp16(fp16)}');
      timeDetection(config);
      for (final file in images) {
        log(
          'img $config ${name(file)} ${_detectStill(file.readAsBytesSync(), out)}',
        );
      }
      try {
        await _live(config, texture, out, log);
      } catch (e) {
        log('live $config FAILED $e');
      }
    }
    // Workers inherit the creating thread's affinity, so rebuild after pinning.
    log('pin a55 ${_pinToA55(arena)}');
    for (final fp16 in [0, 1]) {
      final config = fp16 == 1 ? 'fp16-a55' : 'fp32-a55';
      log('$config set=${clvModelSetFp16(fp16)}');
      timeDetection(config);
    }
  } finally {
    arena.releaseAll();
  }
}

/// Camera on, detection in Kotlin per frame: event rate over 8 s, then one
/// full-resolution still through the still detector.
Future<void> _live(
  String config,
  ValueNotifier<int?> texture,
  Pointer<Float> out,
  void Function(String) log,
) async {
  final host = CameraHostApi();
  final permission = await host.requestPermission();
  if (permission != CameraPermissionStatus.granted) {
    log('live $config permission ${permission.name}');
    return;
  }
  final stamps = <int>[];
  final confidences = <double>[];
  final subscription = cornerFrames().listen((frame) {
    stamps.add(frame.timestampUs);
    if (frame.corners != null) confidences.add(frame.confidence);
  });
  try {
    texture.value = (await host.start()).textureId;
    await Future<void>.delayed(const Duration(seconds: 2));
    stamps.clear();
    confidences.clear();
    await Future<void>.delayed(const Duration(seconds: 8));
    final span = stamps.length < 2 ? 0 : stamps.last - stamps.first;
    final fps = span == 0 ? 0 : (stamps.length - 1) * 1e6 / span;
    confidences.sort();
    log(
      'live $config events=${stamps.length} fps=${fps.toStringAsFixed(1)} '
      'withCorners=${confidences.length} '
      'conf_p50=${confidences.isEmpty ? '-' : confidences[confidences.length ~/ 2].toStringAsFixed(3)}',
    );
    final path = await host.capture();
    log(
      'still $config camera ${_detectStill(File(path).readAsBytesSync(), out, runs: 3)}',
    );
    File(path).deleteSync();
  } finally {
    texture.value = null;
    await host.stop();
    await subscription.cancel();
  }
}

/// Times [runs] detections (the median is logged); the first one runs cold.
String _detectStill(Uint8List bytes, Pointer<Float> out, {int runs = 1}) =>
    using((arena) {
      final input = arena<Uint8>(bytes.length)
        ..asTypedList(bytes.length).setAll(0, bytes);
      final ms = <double>[];
      var status = 0;
      for (var i = 0; i < runs; i++) {
        final watch = Stopwatch()..start();
        status = clvDetectImage(input, bytes.length, out, out + 8);
        ms.add(watch.elapsedMicroseconds / 1000);
      }
      ms.sort();
      return '${_result(status, out)} bytes=${bytes.length} '
          'ms=${ms[runs ~/ 2].toStringAsFixed(1)}';
    }, malloc);

String _result(int status, Pointer<Float> out) {
  final corners = status == ClvStatus.ok
      ? out.asTypedList(8).map((v) => v.toStringAsFixed(4)).join(',')
      : '-';
  final confidence = status >= 0 ? out[8].toStringAsFixed(3) : '-';
  return 'status=$status conf=$confidence corners=$corners';
}

String _times(int runs, void Function() body) {
  for (var i = 0; i < 2; i++) {
    body();
  }
  final ms = <double>[];
  for (var i = 0; i < runs; i++) {
    final watch = Stopwatch()..start();
    body();
    ms.add(watch.elapsedMicroseconds / 1000);
  }
  ms.sort();
  return 'p50=${ms[runs ~/ 2].toStringAsFixed(1)} '
      'p90=${ms[(runs * 0.9).floor().clamp(0, runs - 1)].toStringAsFixed(1)} ms';
}

/// Pins the calling (UI) thread to cpu0-5, the KM6's A55 cluster (D-06).
int _pinToA55(Arena arena) {
  final setAffinity = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Int32, IntPtr, Pointer<Uint64>),
        int Function(int, int, Pointer<Uint64>)
      >('sched_setaffinity');
  return setAffinity(0, 8, arena<Uint64>()..value = 0x3f);
}

Pointer<ClvYuvFrame> _frameFromBmp(Arena arena, Uint8List bmp) {
  final header = ByteData.sublistView(bmp);
  return yuvFrameFromBmp(
    arena,
    bmp,
    header.getInt32(18, Endian.little),
    header.getInt32(22, Endian.little),
    rotation: 90,
  );
}

/// Writes a YUV_420_888 frame into [arena] in sensor orientation: turning it
/// [rotation] degrees clockwise shows the upright 24-bit bottom-up [bmp] of
/// [width]x[height]. Chroma is NV21 (V, U interleaved, pixel stride 2) or I420
/// (planar); every row has [padding] spare bytes. Full-range BT.601, like the
/// camera's YUV.
Pointer<ClvYuvFrame> yuvFrameFromBmp(
  Arena arena,
  Uint8List bmp,
  int width,
  int height, {
  int rotation = 0,
  bool interleaved = true,
  int padding = 0,
}) {
  final turned = rotation % 180 != 0;
  final w = turned ? height : width, h = turned ? width : height;
  final cw = (w + 1) ~/ 2, ch = (h + 1) ~/ 2;
  final bmpRow = (width * 3 + 3) & ~3;
  (int, int) upright(int x, int y) => switch (rotation) {
    90 => (h - 1 - y, x),
    180 => (w - 1 - x, h - 1 - y),
    270 => (y, w - 1 - x),
    _ => (x, y),
  };
  int byte(double v) => v.round().clamp(0, 255);

  final yStride = w + padding;
  final yPlane = arena<Uint8>(yStride * h);
  final cb = Float64List(cw * ch), cr = Float64List(cw * ch);
  final samples = Uint8List(cw * ch);
  for (var sy = 0; sy < h; sy++) {
    for (var sx = 0; sx < w; sx++) {
      final (ux, uy) = upright(sx, sy);
      final at = 54 + (height - 1 - uy) * bmpRow + ux * 3;
      final b = bmp[at], g = bmp[at + 1], r = bmp[at + 2];
      yPlane[sy * yStride + sx] = byte(0.299 * r + 0.587 * g + 0.114 * b);
      final c = (sy >> 1) * cw + (sx >> 1);
      cb[c] += 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
      cr[c] += 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
      samples[c]++;
    }
  }
  final uvStride = (interleaved ? cw * 2 : cw) + padding;
  final Pointer<Uint8> u, v;
  if (interleaved) {
    v = arena<Uint8>(uvStride * ch);
    u = v + 1;
  } else {
    u = arena<Uint8>(uvStride * ch);
    v = arena<Uint8>(uvStride * ch);
  }
  final step = interleaved ? 2 : 1;
  for (var row = 0; row < ch; row++) {
    for (var col = 0; col < cw; col++) {
      final c = row * cw + col;
      u[row * uvStride + col * step] = byte(cb[c] / samples[c]);
      v[row * uvStride + col * step] = byte(cr[c] / samples[c]);
    }
  }
  final frame = arena<ClvYuvFrame>();
  frame.ref
    ..y = yPlane
    ..u = u
    ..v = v
    ..width = w
    ..height = h
    ..yRowStride = yStride
    ..uvRowStride = uvStride
    ..uvPixelStride = step
    ..rotationDegrees = rotation;
  return frame;
}
