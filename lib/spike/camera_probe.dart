// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'probe_b.dart';
import 'probe_camera.dart';
import 'stats.dart';

const candidate = String.fromEnvironment('CANDIDATE', defaultValue: 'A');
const preset = String.fromEnvironment('PRESET', defaultValue: 'medium');

void log(String msg) => print('CLBENCH $candidate/$preset $msg');

ProbeCamera makeCamera() => switch (candidate) {
  'B' => NativeProbeCamera(
    int.parse(preset.split('x').first),
    int.parse(preset.split('x').last),
  ),
  _ => throw UnsupportedError('CANDIDATE=$candidate'),
};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProbeApp());
}

class ProbeApp extends StatefulWidget {
  const ProbeApp({super.key});

  @override
  State<ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<ProbeApp> {
  final ProbeCamera camera = makeCamera();
  bool opened = false;
  String status = 'starting';

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    var done = false;
    void finish() {
      if (done) return;
      done = true;
      log('DONE');
      setState(() => status = 'done');
      unawaited(camera.close().catchError((_) {}));
    }

    final watchdog = Timer(const Duration(seconds: 100), () {
      log('WATCHDOG timeout');
      finish();
    });
    try {
      await Bench(camera, onOpened: () => setState(() => opened = true)).run();
    } catch (e, st) {
      log('ERROR $e ${st.toString().split('\n').take(3).join(' | ')}');
    }
    watchdog.cancel();
    finish();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (opened) Center(child: camera.preview()),
          Positioned(
            left: 16,
            top: 48,
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(),
                ),
                const SizedBox(width: 12),
                Text(
                  '$candidate/$preset $status',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class Bench {
  Bench(this.camera, {required this.onOpened});

  final ProbeCamera camera;
  final VoidCallback onOpened;

  final arrivalsUs = <int>[];
  final interArrivalMs = <double>[];
  final handlerMs = <double>[];
  final nativeLatencyMs = <double>[];
  final frameTimings = <FrameTiming>[];
  String frameSize = '?';
  int bytesPerFrame = 0;
  int lastMeanYUs = 0;

  void onFrame(Uint8List y, int w, int h, int stride, int? nativeUs) {
    final now = Timeline.now;
    if (nativeUs != null) nativeLatencyMs.add((now - nativeUs) / 1000);
    if (arrivalsUs.isNotEmpty) {
      interArrivalMs.add((now - arrivalsUs.last) / 1000);
    }
    arrivalsUs.add(now);
    // The shipped pipeline hands the Y plane to a worker isolate like this.
    TransferableTypedData.fromList([y]);
    handlerMs.add((Timeline.now - now) / 1000);
    frameSize = '${w}x$h stride=$stride';
    bytesPerFrame = y.lengthInBytes;
    if (now - lastMeanYUs > 3000000) {
      lastMeanYUs = now;
      var sum = 0, n = 0;
      for (var i = 0; i < y.length; i += 97) {
        sum += y[i];
        n++;
      }
      log('meanY=${(sum / n).toStringAsFixed(0)}');
    }
  }

  void resetStream() {
    arrivalsUs.clear();
    interArrivalMs.clear();
    handlerMs.clear();
    nativeLatencyMs.clear();
    frameTimings.clear();
  }

  String fps(double seconds) =>
      (arrivalsUs.length / seconds).toStringAsFixed(1);

  void logFrames(String phase) {
    double ms(Duration d) => d.inMicroseconds / 1000;
    final n = frameTimings.length;
    final over = frameTimings
        .where((t) => t.totalSpan > const Duration(microseconds: 16667))
        .length;
    log(
      '$phase uiFrames=$n over16ms=$over '
      'build ${pct([for (final t in frameTimings) ms(t.buildDuration)])} '
      'raster ${pct([for (final t in frameTimings) ms(t.rasterDuration)])}',
    );
  }

  Future<void> measure(String phase, int seconds, {bool stream = true}) async {
    resetStream();
    final cpu0 = threadTicks();
    final sw = Stopwatch()..start();
    await Future<void>.delayed(Duration(seconds: seconds));
    final s = sw.elapsedMicroseconds / 1e6;
    final cpu1 = threadTicks();
    if (stream) {
      log(
        '$phase frame=$frameSize bytes=$bytesPerFrame fps=${fps(s)} '
        'rss=${ProcessInfo.currentRss ~/ 1048576}MB',
      );
      log('$phase interArrivalMs ${pct(interArrivalMs)}');
      log('$phase handlerMs ${pct(handlerMs)}');
      if (nativeLatencyMs.isNotEmpty) {
        log('$phase nativeToDartMs ${pct(nativeLatencyMs)}');
      }
    }
    log('$phase cpu ${cpuDelta(cpu0, cpu1, s)}');
    logFrames(phase);
  }

  Future<void> run() async {
    SchedulerBinding.instance.addTimingsCallback(frameTimings.addAll);
    log('START device=${Platform.operatingSystemVersion}');
    final sw = Stopwatch()..start();
    final info = await camera.open();
    log('OPEN ms=${sw.elapsedMilliseconds} $info');
    onOpened();

    await Future<void>.delayed(const Duration(seconds: 3));
    await measure('previewOnly', 5, stream: false);

    sw.reset();
    await camera.startStream(onFrame);
    log('STREAM start ms=${sw.elapsedMilliseconds}');
    await Future<void>.delayed(const Duration(seconds: 2));
    await measure('stream', 15);
    await logNativeStats();

    resetStream();
    final shotsSw = Stopwatch()..start();
    final shutter = <double>[];
    for (var i = 0; i < 5; i++) {
      try {
        final t = Stopwatch()..start();
        final path = await camera.takePicture();
        final ms = t.elapsedMicroseconds / 1000;
        shutter.add(ms);
        final buf = await ui.ImmutableBuffer.fromFilePath(path);
        final desc = await ui.ImageDescriptor.encoded(buf);
        final bytes = File(path).lengthSync();
        log(
          'STILL $i ms=${ms.toStringAsFixed(0)} '
          '${desc.width}x${desc.height} ${bytes ~/ 1024}KB',
        );
        desc.dispose();
        buf.dispose();
        File(path).deleteSync();
      } catch (e) {
        log('STILL $i ERROR $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final s = shotsSw.elapsedMicroseconds / 1e6;
    log('STILLS shutterMs ${pct(shutter)} streamFpsDuring=${fps(s)}');
    log('STILLS interArrivalMs ${pct(interArrivalMs)}');
    await logNativeStats();

    await _step('FOCUS', () => camera.focus(0.5, 0.5));
    await _step('TORCH on', () => camera.torch(true));
    await Future<void>.delayed(const Duration(seconds: 1));
    await _step('TORCH off', () => camera.torch(false));
    await _step('AELOCK on', () => camera.lockExposure(true));
    await Future<void>.delayed(const Duration(seconds: 1));
    await _step('AELOCK off', () => camera.lockExposure(false));
    await camera.stopStream();
  }

  Future<void> logNativeStats() async {
    final cam = camera;
    if (cam is NativeProbeCamera) log('native ${await cam.stats()}');
  }

  Future<void> _step(String name, Future<Object?> Function() action) async {
    final sw = Stopwatch()..start();
    try {
      final result = await action();
      log('$name ok ms=${sw.elapsedMilliseconds} ${result ?? ''}');
    } catch (e) {
      log('$name ERROR ms=${sw.elapsedMilliseconds} $e');
    }
  }
}
