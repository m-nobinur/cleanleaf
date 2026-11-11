import 'package:flutter/foundation.dart';

/// Tap Scan → page saved timing for both engines, read from logcat by T-020:
/// `CLMETRIC scan_start engine=<e>` then `CLMETRIC scan_saved engine=<e> ms=<n>`.
abstract final class ScanMetrics {
  static Stopwatch? _watch;
  static String _engine = '';

  static void start(String engine) {
    _engine = engine;
    _watch = Stopwatch()..start();
    debugPrint('CLMETRIC scan_start engine=$engine');
  }

  /// Call once the scanned page is stored. No-op without a running [start].
  static void saved() {
    final watch = _watch;
    if (watch == null) return;
    _watch = null;
    debugPrint(
      'CLMETRIC scan_saved engine=$_engine ms=${watch.elapsedMilliseconds}',
    );
  }

  static var _liveFrames = 0;
  static var _liveQuads = 0;
  static Stopwatch? _liveWatch;

  /// Counts live detections reaching the camera screen and logs their rate
  /// every 5 s: `CLMETRIC live fps=<f> quads=<n>`.
  static void liveFrame({required bool hasQuad}) {
    final watch = _liveWatch ??= Stopwatch()..start();
    _liveFrames++;
    if (hasQuad) _liveQuads++;
    final ms = watch.elapsedMilliseconds;
    if (ms < 5000) return;
    final fps = (_liveFrames * 1000 / ms).toStringAsFixed(1);
    debugPrint('CLMETRIC live fps=$fps quads=$_liveQuads');
    _liveFrames = 0;
    _liveQuads = 0;
    watch.reset();
  }
}
