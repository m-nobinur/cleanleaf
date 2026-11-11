import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/geometry/quad.dart';
import 'core/platform/clvision.dart';
import 'core/router/app_router.dart';
import 'features/capture/data/capture_providers.dart';
import 'features/capture/data/pigeon_document_camera.dart';
import 'features/capture/domain/document_camera.dart';
import 'features/capture/domain/scan_mode.dart';

// Device probe for QR / barcode modes (T-029). Push test/fixtures/codes/* to
// the app's external files dir under codes/, grant CAMERA, and read
// `adb logcat -s flutter:I` until `CLBENCH DONE`.
// 1. Decode time and success of each fixture through clv_decode_frame_codes,
//    as a sensor-oriented luma plane (rotation 90, as this phone delivers it).
// 2. The real camera in QR and barcode modes, logging every decode.
// 3. Result sheets for real fixture decodes, injected into the live screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await _fixtures();
  final expected = (jsonDecode(
    File('${dir.path}/expected.json').readAsStringSync(),
  ) as Map<String, dynamic>).cast<String, String?>();
  final decoded = await _bench(dir, expected);

  final camera = _ProbeCamera(PigeonDocumentCamera());
  final container = ProviderContainer(
    overrides: [documentCameraProvider.overrideWithValue(camera)],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CleanleafApp(),
    ),
  );
  await _Script(container.read(routerProvider), camera, decoded).run();
  _log('DONE');
}

void _log(String line) => debugPrint('CLBENCH $line');

Future<Directory> _fixtures() async {
  final root = await getExternalStorageDirectory();
  if (root == null) throw StateError('No external files dir');
  final dir = Directory('${root.path}/codes');
  final manifest = File('${dir.path}/expected.json');
  for (var i = 0; !manifest.existsSync() && i < 90; i++) {
    if (i == 0) _log('waiting for fixtures in ${dir.path}');
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  await Future<void>.delayed(const Duration(seconds: 2)); // let adb finish
  return dir;
}

typedef _Luma = ({Uint8List pixels, int width, int height});

Future<_Luma> _sensorLuma(Uint8List encoded) async {
  final codec = await ui.instantiateImageCodec(encoded);
  final image = (await codec.getNextFrame()).image;
  final rgba = (await image.toByteData())!.buffer.asUint8List();
  final w = image.width, h = image.height;
  // Turn the upright fixture 90° counter-clockwise, so rotation 90 restores it.
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = 4 * (y * w + x);
      out[(w - 1 - x) * h + y] =
          (rgba[i] * 77 + rgba[i + 1] * 150 + rgba[i + 2] * 29) >> 8;
    }
  }
  return (pixels: out, width: h, height: w);
}

Future<Map<String, ScannedCode>> _bench(
  Directory dir,
  Map<String, String?> expected,
) async {
  final decoded = <String, ScannedCode>{};
  _log('clvision opencv=${openCvVersion()}');
  for (final name in expected.keys.toList()..sort()) {
    _log('bench start $name');
    final encoded = File('${dir.path}/$name').readAsBytesSync();
    final luma = await _sensorLuma(encoded);
    final formats = name.startsWith('qr') || name.startsWith('no_')
        ? ClvCodes.matrix
        : ClvCodes.linear;
    final times = <double>[];
    ScannedCode? code;
    using((arena) {
      final y = arena<Uint8>(luma.pixels.length)
        ..asTypedList(luma.pixels.length).setAll(0, luma.pixels);
      final frame = arena<ClvYuvFrame>()
        ..ref.y = y
        ..ref.u = y
        ..ref.v = y
        ..ref.width = luma.width
        ..ref.height = luma.height
        ..ref.yRowStride = luma.width
        ..ref.uvRowStride = luma.width
        ..ref.uvPixelStride = 2
        ..ref.rotationDegrees = 90;
      final out = arena<ClvCode>();
      for (var i = 0; i < 15; i++) {
        final watch = Stopwatch()..start();
        final status = clvDecodeFrameCodes(frame, formats, out);
        times.add(watch.elapsedMicroseconds / 1000);
        if (status == ClvStatus.ok) code = takeCode(out.ref);
      }
    });
    final stillMs = await _stillMs(encoded, formats);
    times.sort();
    final read = code?.text == expected[name];
    if (code case final c?) decoded[name] = c;
    _log(
      'bench $name ${luma.width}x${luma.height} read=$read '
      'format=${code?.format} frame_p50=${times[7].toStringAsFixed(1)} '
      'frame_p90=${times[13].toStringAsFixed(1)} '
      'still_ms=${stillMs.toStringAsFixed(1)}',
    );
  }
  return decoded;
}

Future<double> _stillMs(Uint8List encoded, int formats) async => using((arena) {
  final input = arena<Uint8>(encoded.length)
    ..asTypedList(encoded.length).setAll(0, encoded);
  final out = arena<ClvCode>();
  final watch = Stopwatch()..start();
  final status = clvDecodeImageCodes(input, encoded.length, formats, out);
  final ms = watch.elapsedMicroseconds / 1000;
  if (status == ClvStatus.ok) takeCode(out.ref);
  return ms;
});

/// The real camera, plus codes the script injects into the live screen.
class _ProbeCamera implements DocumentCamera {
  _ProbeCamera(this._inner);

  final DocumentCamera _inner;
  final injected = StreamController<ScannedCode>.broadcast();
  final frames = StreamController<void>.broadcast();

  @override
  late final Stream<LiveDetection> detections = _inner.detections.map((d) {
    frames.add(null);
    return d;
  });

  @override
  late final Stream<ScannedCode> codes = StreamGroup.merge(
    _inner.codes.map((c) {
      _log('live decode format=${c.format} text=${_short(c.text)}');
      return c;
    }),
    injected.stream,
  );

  static String _short(String text) =>
      text.length > 40 ? '${text.substring(0, 40)}…' : text;

  @override
  Future<CameraPermission> requestPermission() => _inner.requestPermission();

  @override
  Future<void> openAppSettings() => _inner.openAppSettings();

  @override
  Future<CameraPreview> start() => _inner.start();

  @override
  Future<void> stop() => _inner.stop();

  @override
  Future<String> capture() => _inner.capture();

  @override
  Future<void> setTorch(bool enabled) => _inner.setTorch(enabled);

  @override
  Future<bool> focusAt(Point point) => _inner.focusAt(point);

  @override
  Future<void> readCodes(CodeFamily? family) => _inner.readCodes(family);

  @override
  Future<bool> openLink(Uri link) async {
    _log('open link host=${link.host}');
    return true;
  }
}

abstract final class StreamGroup {
  static Stream<T> merge<T>(Stream<T> a, Stream<T> b) {
    late final StreamController<T> out;
    final subs = <StreamSubscription<T>>[];
    out = StreamController<T>.broadcast(
      onListen: () => subs.addAll([a.listen(out.add), b.listen(out.add)]),
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
        subs.clear();
      },
    );
    return out.stream;
  }
}

class _Script {
  _Script(this.router, this.camera, this.decoded);

  final GoRouter router;
  final _ProbeCamera camera;
  final Map<String, ScannedCode> decoded;

  Future<void> run() async {
    await _pause(2000);
    await _live(ScanMode.qrCode, seconds: 25);
    await _live(ScanMode.barcode, seconds: 20);
    await _sheet(ScanMode.qrCode, 'qr_v10_4.0ppm.jpg', 'result_qr_link');
    await _sheet(ScanMode.qrCode, 'qr_utf8.jpg', 'result_qr_text');
    await _sheet(ScanMode.barcode, 'ean13_2.0ppm.jpg', 'result_ean13');
    router.go('/');
    await _pause(1000);
  }

  Future<void> _open(ScanMode mode) async {
    router.go('/');
    await _pause(800);
    unawaited(router.push('/capture?mode=${mode.name}'));
    try {
      await camera.frames.stream.first.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      _log('ERROR mode=${mode.name}: no camera events within 15 s');
    }
  }

  /// Point the phone at codes on the Mac screen during this window.
  Future<void> _live(ScanMode mode, {required int seconds}) async {
    await _open(mode);
    var n = 0;
    final sub = camera.frames.stream.listen((_) => n++);
    _log('SHOT camera_${mode.name}');
    _log('LIVE ${mode.name} start, ${seconds}s');
    await _pause(seconds * 1000);
    await sub.cancel();
    _log('LIVE ${mode.name} frames_per_s=${(n / seconds).toStringAsFixed(1)}');
  }

  Future<void> _sheet(ScanMode mode, String fixture, String shot) async {
    final code = decoded[fixture];
    if (code == null) {
      _log('ERROR $fixture did not decode on device; no $shot');
      return;
    }
    await _open(mode);
    await _pause(1500);
    camera.injected.add(code);
    await _pause(800);
    _log('SHOT $shot');
    await _pause(6000);
  }

  Future<void> _pause(int ms) => Future.delayed(Duration(milliseconds: ms));
}
