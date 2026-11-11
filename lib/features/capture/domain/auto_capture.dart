import 'dart:math' as math;

import '../../../core/geometry/quad.dart';
import 'document_camera.dart';

/// Fires once per stable page: after a shot it re-arms only when the page
/// leaves the frame or moves to a clearly different place, so returning from
/// a retake over the same resting page does not shoot it again.
class AutoCapture {
  AutoCapture({this.moveTolerance = 0.08, this.missingFrames = 5});

  /// Largest corner move (normalized) still counted as the same page.
  final double moveTolerance;

  /// Consecutive frames without a page before the page counts as gone.
  final int missingFrames;

  Quad? _shot;
  int _missing = 0;

  /// False after a shot until the page leaves or moves.
  bool get isArmed => _shot == null;

  /// Feeds one live detection; true when it should trigger a capture.
  bool onDetection(LiveDetection detection) {
    final quad = detection.quad;
    if (quad == null) {
      if (++_missing >= missingFrames) _shot = null;
      return false;
    }
    _missing = 0;
    final shot = _shot;
    if (shot != null && _maxCornerMove(shot, quad) > moveTolerance) {
      _shot = null;
    }
    if (!detection.isStable || _shot != null) return false;
    _shot = quad;
    return true;
  }

  /// Marks [quad] as already shot, e.g. after a manual shutter press.
  void markShot(Quad? quad) => _shot = quad;

  static double _maxCornerMove(Quad a, Quad b) {
    var max = 0.0;
    final bs = b.corners;
    for (final (i, p) in a.corners.indexed) {
      final dx = p.x - bs[i].x;
      final dy = p.y - bs[i].y;
      max = math.max(max, math.sqrt(dx * dx + dy * dy));
    }
    return max;
  }
}
