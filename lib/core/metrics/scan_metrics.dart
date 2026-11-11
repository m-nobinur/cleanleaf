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
}
