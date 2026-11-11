import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'core/platform/camera_api.g.dart';

// Device probe for the CameraX module: run with -t after granting CAMERA and
// read `adb logcat -s flutter:I` until `CLBENCH DONE`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final probe = _Probe();
  runApp(_ProbeView(probe.session));
  await probe.run();
  _log('DONE');
}

void _log(String line) => debugPrint('CLBENCH $line');

typedef _Event = ({int arrivalUs, CornerFrame frame});

class _Probe {
  final host = CameraHostApi();
  final session = ValueNotifier<CameraSession?>(null);
  final clock = Stopwatch()..start();
  final events = <_Event>[];
  final timings = <ui.FrameTiming>[];
  Completer<void>? firstFrame;

  Future<void> run() async {
    cornerFrames().listen((frame) {
      events.add((arrivalUs: clock.elapsedMicroseconds, frame: frame));
      firstFrame?.complete();
      firstFrame = null;
    }, onError: (Object e) => _log('stream error $e'));
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);

    await _step(
      'permission',
      () async => (await host.requestPermission()).name,
    );
    _log('mem launch ${_memory()}');
    await _step('session', _openFirst);
    await _step('stream', _streamWindow);
    await _step('torch', _torch);
    await _step('focus', _focus);
    await _step('capture', _captures);
    await _step('stop', () async {
      await _close();
      return 'capture after stop: ${await _errorCode(host.capture)}';
    });
    await _step('cycles', _cycles);
  }

  Future<void> _step(String name, Future<String> Function() body) async {
    try {
      _log('$name ${await body()}');
    } catch (e) {
      _log('$name FAILED $e');
    }
  }

  Future<String> _openFirst() async {
    final (startMs, firstMs) = await _open();
    final s = session.value!;
    return 'start=${startMs}ms firstFrame=${firstMs}ms texture=${s.textureId} '
        'preview=${s.previewWidth}x${s.previewHeight} '
        'analysis=${s.analysisWidth}x${s.analysisHeight} '
        'capture=${s.captureWidth}x${s.captureHeight} '
        'sensorRotation=${s.sensorRotation} '
        'handlesCropAndRotation=${s.handlesCropAndRotation}';
  }

  Future<String> _streamWindow() async {
    const window = Duration(seconds: 10);
    events.clear();
    timings.clear();
    await Future<void>.delayed(window);
    final frames = [...events.map((e) => e.frame)];
    final sensorMs = _deltas(frames.map((f) => f.timestampUs)).map(_ms);
    final arrivalMs = _deltas(events.map((e) => e.arrivalUs)).map(_ms);
    final rasterMs = timings.map((t) => _ms(t.rasterDuration.inMicroseconds));
    final seconds = window.inMilliseconds / 1000;
    return 'events=${frames.length} '
        'eventFps=${_f(frames.length / seconds)} '
        'streamFps=${_f(1000 / _pct(sensorMs, 0.5))} '
        'sensorDeltaMs p50=${_f(_pct(sensorMs, 0.5))} '
        'p95=${_f(_pct(sensorMs, 0.95))} max=${_f(_pct(sensorMs, 1))} '
        'arrivalDeltaMs p50=${_f(_pct(arrivalMs, 0.5))} '
        'p95=${_f(_pct(arrivalMs, 0.95))} max=${_f(_pct(arrivalMs, 1))} '
        'withCorners=${frames.where((f) => f.corners != null).length} '
        'stable=${frames.where((f) => f.isStable).length} '
        'flutterFrames=${timings.length} '
        'flutterFps=${_f(timings.length / seconds)} '
        'rasterMs p90=${_f(_pct(rasterMs, 0.9))}';
  }

  Future<String> _torch() async {
    final on = await _timed(() => host.setTorch(true));
    final off = await _timed(() => host.setTorch(false));
    return 'on=${on.$1}ms off=${off.$1}ms';
  }

  Future<String> _focus() async {
    final centre = await _timed(() => host.focusAt(0.5, 0.5));
    final corner = await _timed(() => host.focusAt(0.25, 0.25));
    return 'centre=${centre.$2} ${centre.$1}ms '
        'topLeftQuarter=${corner.$2} ${corner.$1}ms';
  }

  Future<String> _captures() async {
    final before = events.length;
    final started = clock.elapsedMicroseconds;
    final lines = <String>[];
    for (var i = 0; i < 3; i++) {
      final (ms, path) = await _timed(host.capture);
      final file = File(path);
      final bytes = await file.length();
      final size = await _jpegSize(path);
      lines.add('#$i ${ms}ms $path bytes=$bytes decoded=$size');
      await file.delete();
    }
    final seconds = (clock.elapsedMicroseconds - started) / 1e6;
    final s = session.value!;
    return '${lines.join(' | ')} | '
        'session=${s.captureWidth}x${s.captureHeight} '
        'eventFpsDuringCapture=${_f((events.length - before) / seconds)}';
  }

  Future<String> _cycles() async {
    const count = 20;
    final startMs = <num>[];
    final firstMs = <num>[];
    var noFrame = 0;
    String? baseline;
    for (var i = 1; i <= count; i++) {
      final (start, first) = await _open();
      startMs.add(start);
      if (first < 0) {
        noFrame++;
      } else {
        firstMs.add(first);
      }
      await _close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (i == 1) baseline = _memory();
    }
    final after = _memory();
    await Future<void>.delayed(const Duration(seconds: 3));
    return '$count cycles noFrame=$noFrame '
        'startMs p50=${_pct(startMs, 0.5)} max=${_pct(startMs, 1)} '
        'firstFrameMs p50=${_pct(firstMs, 0.5)} max=${_pct(firstMs, 1)} '
        '| after1: $baseline | after$count: $after '
        '| settled3s: ${_memory()}';
  }

  /// Returns ms to `start()` and ms to the first corner event, -1 if none.
  Future<(int, int)> _open() async {
    final began = clock.elapsedMilliseconds;
    final first = Completer<void>();
    firstFrame = first;
    final s = await host.start();
    final started = clock.elapsedMilliseconds - began;
    session.value = s;
    try {
      await first.future.timeout(const Duration(seconds: 3));
      return (started, clock.elapsedMilliseconds - began);
    } on TimeoutException {
      return (started, -1);
    }
  }

  Future<void> _close() async {
    session.value = null;
    await host.stop();
  }

  Future<(int, T)> _timed<T>(Future<T> Function() body) async {
    final began = clock.elapsedMilliseconds;
    final result = await body();
    return (clock.elapsedMilliseconds - began, result);
  }
}

Future<String> _errorCode(Future<Object?> Function() body) async {
  try {
    await body();
    return 'no error';
  } on PlatformException catch (e) {
    return e.code;
  }
}

Future<String> _jpegSize(String path) async {
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final size = '${descriptor.width}x${descriptor.height}';
  descriptor.dispose();
  buffer.dispose();
  return size;
}

String _memory() {
  String field(String text, String key) =>
      RegExp('^$key:\\s+(\\d+)', multiLine: true).firstMatch(text)?.group(1) ??
      '?';
  final status = File('/proc/self/status').readAsStringSync();
  final rollup = File('/proc/self/smaps_rollup');
  final pss = rollup.existsSync()
      ? field(rollup.readAsStringSync(), 'Pss')
      : '?';
  final fds = Directory('/proc/self/fd').listSync().length;
  return 'pssKb=$pss rssKb=${field(status, 'VmRSS')} '
      'threads=${field(status, 'Threads')} fds=$fds';
}

Iterable<int> _deltas(Iterable<int> values) {
  final list = values.toList();
  return [for (var i = 1; i < list.length; i++) list[i] - list[i - 1]];
}

double _ms(int us) => us / 1000;

num _pct(Iterable<num> values, double p) {
  final sorted = values.toList()..sort();
  return sorted.isEmpty
      ? double.nan
      : sorted[((sorted.length - 1) * p).round()];
}

String _f(num value) => value.toStringAsFixed(1);

class _ProbeView extends StatelessWidget {
  const _ProbeView(this.session);

  final ValueListenable<CameraSession?> session;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        ValueListenableBuilder<CameraSession?>(
          valueListenable: session,
          builder: (context, s, _) => s == null
              ? const SizedBox.shrink()
              : Center(
                  child: AspectRatio(
                    aspectRatio: (s.sensorRotation ~/ 90).isOdd
                        ? s.previewHeight / s.previewWidth
                        : s.previewWidth / s.previewHeight,
                    child: RotatedBox(
                      quarterTurns: s.handlesCropAndRotation
                          ? 0
                          : s.sensorRotation ~/ 90,
                      child: Texture(textureId: s.textureId),
                    ),
                  ),
                ),
        ),
        // Keeps Flutter drawing every vsync, so frame counts measure UI headroom.
        const Align(
          alignment: Alignment.bottomCenter,
          child: CircularProgressIndicator(),
        ),
      ],
    ),
  );
}
