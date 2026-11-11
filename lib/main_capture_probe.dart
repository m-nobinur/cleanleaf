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
import 'core/platform/clvision.dart';
import 'core/router/app_router.dart';
import 'core/router/app_routes.dart';
import 'features/capture/data/capture_providers.dart';
import 'features/capture/data/pigeon_document_camera.dart';
import 'features/capture/domain/document_camera.dart';
import 'features/capture/presentation/auto_capture_setting.dart';
import 'features/editor/presentation/editor_providers.dart';
import 'features/gallery_import/data/detect_still_quad.dart';
import 'features/gallery_import/data/gallery_import.dart';
import 'features/gallery_import/presentation/import_from_gallery.dart';
import 'features/library/data/library_providers.dart';

// Device probe for the camera screen (T-008, T-027): run with -t, grant CAMERA, push
// real photos (+ optional labels.json) to the app's external files dir, and
// read `adb logcat -s flutter:I` until `CLBENCH DONE`. The live preview and
// event cadence are the real camera's, but the outline is the photo's
// labelled quad and each shot returns that photo instead of the still, so
// the crop review shows a real page (re-detected by the model, else the
// label). An import step feeds a photo through the gallery import.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final photos = await _Photos.load();
  final camera = _ProbeCamera(PigeonDocumentCamera(), photos);
  final container = ProviderContainer(
    overrides: [
      documentCameraProvider.overrideWithValue(camera),
      // The system picker needs taps; import the current photo instead.
      galleryImportProvider.overrideWith(
        (ref) => GalleryImport(
          pick: () async => camera.photo.file.path,
          detect: detectStillQuad,
          documents: ref.watch(documentRepositoryProvider),
          pages: ref.watch(pageRepositoryProvider),
        ),
      ),
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CleanleafApp(),
    ),
  );
  // Still re-detection on the photos uses the real model, as in main.dart.
  unawaited(loadDocAligner());
  // Earlier probe runs may have left Auto off in this package's settings.
  final auto = container.read(autoCaptureSettingProvider.notifier);
  _log(
    'auto_capture_was=${await container.read(autoCaptureSettingProvider.future)}',
  );
  await auto.set(true);
  await _Script(container, camera, photos).run();
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
    // Reinstalling wipes this dir, so the photos may be pushed after launch.
    var files = _images(dir);
    for (var i = 0; files.isEmpty && i < 60; i++) {
      if (i == 0) _log('waiting for photos in ${dir.path}');
      await Future<void>.delayed(const Duration(seconds: 2));
      files = _images(dir);
    }
    await Future<void>.delayed(const Duration(seconds: 2)); // let adb finish
    files = _images(dir);
    final labelsFile = File('${dir.path}/labels.json');
    final labels = labelsFile.existsSync()
        ? jsonDecode(labelsFile.readAsStringSync()) as Map<String, dynamic>
        : const <String, dynamic>{};
    if (files.isEmpty) throw StateError('No photos in ${dir.path}');
    final photos = [
      for (final f in files)
        (file: f, quad: _quad(labels[f.uri.pathSegments.last]) ?? _unlabelled),
    ];
    _log('photos n=${photos.length} labelled=${labels.length} dir=${dir.path}');
    return _Photos(photos);
  }

  static List<File> _images(Directory dir) =>
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
  _Script(this.container, this.camera, this.photos)
    : router = container.read(routerProvider);

  final ProviderContainer container;
  final GoRouter router;
  final _ProbeCamera camera;
  final _Photos photos;
  final clock = Stopwatch()..start();

  String get _location => router.state.matchedLocation;

  Future<void> run() async {
    await _pause(2000);
    await _scan('document', photos.pick(receipt: false), measureUi: true);
    await _scan('receipt', photos.pick(receipt: true));
    for (final mode in ['idCard', 'passport', 'book']) {
      await _open(mode);
      await _shot('camera_${mode.toLowerCase()}');
    }
    await _lifecycle();
    // Last, so the review stays open for theme and drag shots after DONE.
    await _import(photos.pick(receipt: false));
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
    while (!_location.startsWith('/editor')) {
      await _pause(20);
      if (clock.elapsedMilliseconds - shutter > 10000) {
        _log('ERROR no auto-capture within 10 s');
        return;
      }
    }
    _log(
      'auto_capture_to_editor_route ms=${clock.elapsedMilliseconds - shutter}',
    );
    camera.show = _Show.nothing;
    await _editorReady('auto_capture_to_editor_ready mode=$mode', shutter);
    await _shot('review_$mode');
    router.pop();
    await _firstEvent('retake mode=$mode', clock.elapsedMilliseconds);
  }

  Future<void> _import(_Photo photo) async {
    camera.show = _Show.nothing;
    router.go('/');
    await _pause(500);
    camera.photo = photo;
    final start = clock.elapsedMilliseconds;
    final page = await container.read(galleryImportProvider)();
    unawaited(router.push(AppRoutes.editor(page!.id, fresh: true)));
    await _editorReady('import_to_editor_ready', start);
    await _shot('review_import');
  }

  /// Logs when the review shows its photo: the route is up and the decode the
  /// crop canvas waits on has finished, plus one painted frame.
  Future<void> _editorReady(String label, int since) async {
    while (!_location.startsWith('/editor')) {
      await _pause(20);
    }
    final pageId = router.state.pathParameters['pageId']!;
    final page = await container.read(pageRepositoryProvider).get(pageId);
    // Listening keeps the auto-dispose provider alive while it decodes.
    final image = container.listen(
      pageImageProvider(page!.originalPath).future,
      (_, _) {},
    );
    await image.read();
    image.close();
    await SchedulerBinding.instance.endOfFrame;
    _log('$label ms=${clock.elapsedMilliseconds - since}');
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
