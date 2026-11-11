import 'package:cleanleaf/core/geometry/quad.dart';

import 'scan_mode.dart';

enum CameraPermission { granted, denied, permanentlyDenied }

enum CameraFailure implements Exception {
  permissionDenied,

  /// A camera call came before `start` or after the session ended.
  notStarted,

  /// Another app holds the camera; the session resumes once it is released.
  inUse,

  /// Blocked by device policy or Do Not Disturb.
  disabled,
  captureFailed,
  unavailable,
}

/// [width] and [height] are the upright preview size. Wrap the texture in a
/// `RotatedBox(quarterTurns: quarterTurns)` to show it upright.
typedef CameraPreview = ({
  int textureId,
  int width,
  int height,
  int quarterTurns,
  bool hasTorch,
});

/// Page detection for one live frame; [quad] is null when no page is found.
typedef LiveDetection = ({Quad? quad, double confidence, bool isStable});

/// A QR code or barcode read from a live frame or a photo; never stored
/// (D-47). [format] is a display name such as "QR Code" or "EAN-13".
typedef ScannedCode = ({String format, String text});

extension ScannedCodeLink on ScannedCode {
  /// The text as an http(s) link, or null; only these get an Open action.
  Uri? get webLink {
    final uri = Uri.tryParse(text.trim());
    final web = uri != null && (uri.isScheme('http') || uri.isScheme('https'));
    return web && uri.host.isNotEmpty ? uri : null;
  }
}

/// The back camera, with page detection running on its live frames.
///
/// Frames, corners and stills are oriented to the device's natural (portrait)
/// orientation, so the camera screen should lock portrait. The session ends on
/// [stop] or when the app pauses; call [start] again on resume.
abstract interface class DocumentCamera {
  Future<CameraPermission> requestPermission();

  Future<void> openAppSettings();

  Future<CameraPreview> start();

  Future<void> stop();

  /// Full-resolution JPEG path in the app cache; the caller moves or deletes it.
  Future<String> capture();

  Future<void> setTorch(bool enabled);

  /// [point] is normalized to the upright preview; true when focus locked.
  Future<bool> focusAt(Point point);

  /// Errors on this stream are [CameraFailure]s raised while running.
  Stream<LiveDetection> get detections;

  /// Reads [family] codes on live frames instead of detecting pages; null
  /// goes back to pages. Holds across [start] calls.
  Future<void> readCodes(CodeFamily? family);

  /// Codes found while [readCodes] is on, one event per frame that has one.
  Stream<ScannedCode> get codes;

  /// Opens an http(s) link in another app; false when nothing can.
  Future<bool> openLink(Uri link);
}
