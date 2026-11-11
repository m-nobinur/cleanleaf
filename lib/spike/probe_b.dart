import 'dart:async';
import 'dart:developer';

import 'package:flutter/widgets.dart';

import 'camera_probe_api.g.dart';
import 'probe_camera.dart';

class NativeProbeCamera implements ProbeCamera {
  NativeProbeCamera(this.analysisWidth, this.analysisHeight);

  final int analysisWidth;
  final int analysisHeight;
  final _api = CameraProbeHostApi();
  late CameraInfoMsg _info;
  StreamSubscription<FrameMsg>? _sub;

  @override
  Future<Map<String, Object?>> open() async {
    _info = await _api.open(analysisWidth, analysisHeight);
    final before = Timeline.now;
    final native = await _api.monotonicNowUs();
    final after = Timeline.now;
    return {
      'preview': '${_info.previewWidth}x${_info.previewHeight}',
      'analysis': '${_info.analysisWidth}x${_info.analysisHeight}',
      'capture': '${_info.captureWidth}x${_info.captureHeight}',
      'handlesCropAndRotation': _info.handlesCropAndRotation,
      'sensorRotation': _info.sensorRotation,
      'clockSkewUs': native - (before + after) ~/ 2,
      'clockCallUs': after - before,
      'details': _info.details,
    };
  }

  @override
  Widget preview() {
    final turns = _info.handlesCropAndRotation ? 0 : _info.sensorRotation ~/ 90;
    return AspectRatio(
      aspectRatio: _info.previewHeight / _info.previewWidth,
      child: RotatedBox(
        quarterTurns: turns,
        child: Texture(textureId: _info.textureId),
      ),
    );
  }

  @override
  Future<void> startStream(FrameHandler onFrame) async {
    _sub = frames().listen(
      (f) => onFrame(f.y, f.width, f.height, f.rowStride, f.stampUs),
    );
    await _api.startStream();
  }

  @override
  Future<void> stopStream() async {
    await _api.stopStream();
    await _sub?.cancel();
  }

  @override
  Future<String> takePicture() => _api.takePicture();

  @override
  Future<String> focus(double x, double y) => _api.focus(x, y);

  @override
  Future<void> torch(bool on) => _api.torch(on);

  @override
  Future<void> lockExposure(bool locked) => _api.lockExposure(locked);

  Future<String> stats() => _api.stats();

  @override
  Future<void> close() => _api.close();
}
