import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/geometry/quad.dart';
import '../../../core/platform/camera_api.g.dart';
import '../../../core/platform/clvision.dart' show ClvCodes;
import '../domain/document_camera.dart';
import '../domain/scan_mode.dart';

/// [DocumentCamera] over the Kotlin CameraX module (`camera/CameraHost.kt`).
/// Its `FlutterError` codes are [CameraFailure] names.
class PigeonDocumentCamera implements DocumentCamera {
  PigeonDocumentCamera({CameraHostApi? host, Stream<CornerFrame>? frames})
    : _host = host ?? CameraHostApi(),
      _frames = frames ?? cornerFrames();

  final CameraHostApi _host;
  final Stream<CornerFrame> _frames;

  // One shared subscription: a second EventChannel listener would replace the
  // first.
  late final Stream<CornerFrame> _shared = _frames.asBroadcastStream();

  @override
  late final Stream<LiveDetection> detections = _shared
      .map(_detection)
      .transform(
        StreamTransformer.fromHandlers(
          handleError: (error, stack, sink) =>
              sink.addError(_failure(error), stack),
        ),
      );

  // Errors reach listeners through [detections].
  @override
  late final Stream<ScannedCode> codes = _shared
      .handleError((Object _) {})
      .where((frame) => frame.code != null)
      .map((frame) => (format: frame.code!.format, text: frame.code!.text));

  @override
  Future<void> readCodes(CodeFamily? family) => _call(
    () => _host.setCodeFormats(switch (family) {
      null => 0,
      CodeFamily.matrix => ClvCodes.matrix,
      CodeFamily.linear => ClvCodes.linear,
    }),
  );

  @override
  Future<bool> openLink(Uri link) => _call(() => _host.openUrl('$link'));

  @override
  Future<CameraPermission> requestPermission() async =>
      switch (await _call(_host.requestPermission)) {
        CameraPermissionStatus.granted => CameraPermission.granted,
        CameraPermissionStatus.denied => CameraPermission.denied,
        CameraPermissionStatus.permanentlyDenied =>
          CameraPermission.permanentlyDenied,
      };

  @override
  Future<void> openAppSettings() => _call(_host.openAppSettings);

  @override
  Future<CameraPreview> start() => _call(() async {
    final session = await _host.start();
    final capabilities = await _host.capabilities();
    final turns = session.sensorRotation ~/ 90;
    final sideways = turns.isOdd;
    return (
      textureId: session.textureId,
      width: sideways ? session.previewHeight : session.previewWidth,
      height: sideways ? session.previewWidth : session.previewHeight,
      quarterTurns: session.handlesCropAndRotation ? 0 : turns,
      hasTorch: capabilities?.hasTorch ?? false,
    );
  });

  @override
  Future<void> stop() => _call(_host.stop);

  @override
  Future<String> capture() => _call(_host.capture);

  @override
  Future<void> setTorch(bool enabled) => _call(() => _host.setTorch(enabled));

  @override
  Future<bool> focusAt(Point point) =>
      _call(() => _host.focusAt(point.x, point.y));

  static Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw _failure(e);
    }
  }

  static Object _failure(Object error) => error is PlatformException
      ? CameraFailure.values.asNameMap()[error.code] ??
            CameraFailure.unavailable
      : error;

  static LiveDetection _detection(CornerFrame frame) => (
    quad: switch (frame.corners) {
      [
        final x0,
        final y0,
        final x1,
        final y1,
        final x2,
        final y2,
        final x3,
        final y3,
      ] =>
        (
          topLeft: (x: x0, y: y0),
          topRight: (x: x1, y: y1),
          bottomRight: (x: x2, y: y2),
          bottomLeft: (x: x3, y: y3),
        ),
      _ => null,
    },
    confidence: frame.confidence,
    isStable: frame.isStable,
  );
}
