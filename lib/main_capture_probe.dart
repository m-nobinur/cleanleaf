import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/geometry/quad.dart';
import 'core/router/app_router.dart';
import 'features/capture/data/capture_providers.dart';
import 'features/capture/data/pigeon_document_camera.dart';
import 'features/capture/domain/document_camera.dart';

// Device probe for the camera screen (T-008): run with -t, grant CAMERA, push
// real photos (+ optional labels.json) to the app's external files dir, and
// read `adb logcat -s flutter:I` until `CLBENCH DONE`. The live preview and
// event cadence are the real camera's; until T-005 lands the outline is the
// photo's labelled quad, and each shot returns that photo instead of the
// still, so confirm shows a real page.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final photos = await _Photos.load();
  final camera = _ProbeCamera(PigeonDocumentCamera(), photos);
  final container = ProviderContainer(
    overrides: [documentCameraProvider.overrideWithValue(camera)],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CleanleafApp(),
    ),
  );
  await _Script(container.read(routerProvider), camera, photos).run();
  _log('DONE');
}

void _log(String line) => debugPrint('CLBENCH $line');

typedef _Photo = ({File file, Quad quad});

class _Photos {
  _Photos(this.all);

  final List<_Photo> all;

  static const Quad _unlabelled = (
    topLeft: (x: 0.1, y: 0.1),
    topRight: (x: 0.9, y: 0.1),
    bottomRight: (x: 0.9, y: 0.9),
    bottomLeft: (x: 0.1, y: 0.9),
  );

  static Future<_Photos> load() async {
    final dir = await getExternalStorageDirectory();
    if (dir == null) throw StateError('No external files dir');
    final labelsFile = File('${dir.path}/labels.json');
    final labels = labelsFile.existsSync()
        ? jsonDecode(labelsFile.readAsStringSync()) as Map<String, dynamic>
        : const <String, dynamic>{};
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) => RegExp(
                r'\.(jpe?g|png)$',
                caseSensitive: false,
              ).hasMatch(f.path),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) throw StateError('No photos in ${dir.path}');
    final photos = [
      for (final f in files)
        (file: f, quad: _quad(labels[f.uri.pathSegments.last]) ?? _unlabelled),
    ];
    _log('photos n=${photos.length} labelled=${labels.length} dir=${dir.path}');
    return _Photos(photos);
  }

  static Quad? _quad(Object? label) {
    if (label is! Map || label['corners'] is! List) return null;
    final c = [
      for (final p in label['corners'] as List)
        (x: (p as List)[0] as num, y: p[1] as num),
    ];
    Point at(int i) => (x: c[i].x.toDouble(), y: c[i].y.toDouble());
    return (
      topLeft: at(0),
      topRight: at(1),
      bottomRight: at(2),
      bottomLeft: at(3),
    );
  }

  _Photo pick({required bool receipt}) {
    final named = all.where(
      (p) => p.file.path.toLowerCase().contains('receipt') == receipt,
    );
    return named.firstOrNull ?? all[receipt && all.length > 1 ? 1 : 0];
  }
}

enum _Show { nothing, moving, resting }

/// The real camera, with scripted page outlines and real photos as stills.
class _ProbeCamera implements DocumentCamera {
  _ProbeCamera(this._inner, this._photos);

  final DocumentCamera _inner;
  final _Photos _photos;
  var show = _Show.nothing;
  late _Photo photo = _photos.all.first;
  var _frame = 0;
  final events = StreamController<int>.broadcast();

  @override
  late final Stream<LiveDetection> detections = _inner.detections.map((real) {
    events.add(++_frame);
    final q = photo.quad;
    return switch (show) {
      _Show.nothing => (quad: null, confidence: 0, isStable: false),
      _Show.moving => (
        quad: _shift(
          q,
          0.03 * math.sin(_frame / 2),
          0.02 * math.cos(_frame / 3),
        ),
        confidence: 0.9,
        isStable: false,
      ),
      _Show.resting => (quad: q, confidence: 0.9, isStable: true),
    };
  });

  static Quad _shift(Quad q, double dx, double dy) {
    Point s(Point p) => (x: p.x + dx, y: p.y + dy);
    return (
      topLeft: s(q.topLeft),
      topRight: s(q.topRight),
      bottomRight: s(q.bottomRight),
      bottomLeft: s(q.bottomLeft),
    );
  }

  @override
  Future<String> capture() async {
    final still = File(await _inner.capture());
    final copy = File('${still.parent.path}/probe_$_frame.jpg');
    await photo.file.copy(copy.path);
    await still.delete();
    _log('capture photo=${photo.file.uri.pathSegments.last}');
    return copy.path;
  }

  @override
  Future<CameraPermission> requestPermission() => _inner.requestPermission();

  @override
  Future<void> openAppSettings() => _inner.openAppSettings();

  @override
  Future<CameraPreview> start() => _inner.start();

  @override
  Future<void> stop() => _inner.stop();

  @override
  Future<void> setTorch(bool enabled) => _inner.setTorch(enabled);

  @override
  Future<bool> focusAt(Point point) => _inner.focusAt(point);
}

class _Script {
  _Script(this.router, this.camera, this.photos);

  final GoRouter router;
  final _ProbeCamera camera;
  final _Photos photos;
  final clock = Stopwatch()..start();

  String get _location => router.state.matchedLocation;

  Future<void> run() async {
    await _pause(2000);
    await _scan('document', photos.pick(receipt: false), measureUi: true);
    await _scan('receipt', photos.pick(receipt: true));
    await _open('idCard');
    camera.show = _Show.nothing;
    await _shot('camera_idcard');
    await _lifecycle();
  }

  Future<void> _open(String mode) async {
    camera.show = _Show.nothing;
    router.go('/');
    await _pause(500);
    final opened = clock.elapsedMilliseconds;
    unawaited(router.push('/capture?mode=$mode'));
    await _firstEvent('open mode=$mode', opened);
  }

  Future<void> _scan(
    String mode,
    _Photo photo, {
    bool measureUi = false,
  }) async {
    await _open(mode);
    camera.photo = photo;
    await _shot('camera_${mode}_guide');
    camera.show = _Show.moving;
    final timings = <ui.FrameTiming>[];
    if (measureUi) SchedulerBinding.instance.addTimingsCallback(timings.addAll);
    final events = _count(camera.events.stream);
    await _shot('camera_${mode}_arming');
    _log(
      'overlay mode=$mode events_per_s=${(await events()).toStringAsFixed(1)}',
    );
    if (measureUi) {
      SchedulerBinding.instance.removeTimingsCallback(timings.addAll);
      _logUi(timings);
    }
    camera.show = _Show.resting;
    final shutter = clock.elapsedMilliseconds;
    while (!_location.startsWith('/confirm')) {
      await _pause(20);
      if (clock.elapsedMilliseconds - shutter > 10000) {
        _log('ERROR no auto-capture within 10 s');
        return;
      }
    }
    _log(
      'auto_capture_to_confirm_route ms=${clock.elapsedMilliseconds - shutter}',
    );
    camera.show = _Show.nothing;
    await _shot('confirm_$mode');
    router.pop();
    await _firstEvent('retake mode=$mode', clock.elapsedMilliseconds);
  }

  Future<void> _lifecycle() async {
    _log('LIFECYCLE press HOME now, relaunch after 3 s');
    final resumed = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () => resumed.isCompleted ? null : resumed.complete(),
    );
    try {
      await resumed.future.timeout(const Duration(seconds: 90));
      final at = clock.elapsedMilliseconds;
      await camera.events.stream.first.timeout(const Duration(seconds: 10));
      _log('resume_to_first_event ms=${clock.elapsedMilliseconds - at}');
    } on TimeoutException {
      _log('ERROR lifecycle: no resume or no frames after resume');
    } finally {
      listener.dispose();
    }
  }

  Future<void> _firstEvent(String label, int since) async {
    try {
      await camera.events.stream.first.timeout(const Duration(seconds: 15));
      _log('$label first_event_ms=${clock.elapsedMilliseconds - since}');
    } on TimeoutException {
      _log('ERROR $label: no camera events within 15 s');
    }
  }

  Future<void> _shot(String name) async {
    _log('SHOT $name');
    await _pause(6000);
  }

  /// Events per second from now until the returned function is called.
  Future<double> Function() _count(Stream<int> events) {
    var n = 0;
    final start = clock.elapsedMilliseconds;
    final sub = events.listen((_) => n++);
    return () async {
      await sub.cancel();
      return n * 1000 / (clock.elapsedMilliseconds - start);
    };
  }

  void _logUi(List<ui.FrameTiming> timings) {
    if (timings.isEmpty) {
      _log('ui frames=0');
      return;
    }
    double p(List<int> v, double q) =>
        (v..sort())[((v.length - 1) * q).round()] / 1000;
    final build = [for (final t in timings) t.buildDuration.inMicroseconds];
    final raster = [for (final t in timings) t.rasterDuration.inMicroseconds];
    _log(
      'ui frames=${timings.length} fps=${(timings.length / 6).toStringAsFixed(1)} '
      'build_p50=${p(build, .5)} build_p90=${p(build, .9)} '
      'raster_p50=${p(raster, .5)} raster_p90=${p(raster, .9)} ms',
    );
  }

  Future<void> _pause(int ms) => Future.delayed(Duration(milliseconds: ms));
}
