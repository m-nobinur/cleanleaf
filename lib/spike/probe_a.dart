import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'probe_camera.dart';

class PluginProbeCamera implements ProbeCamera {
  PluginProbeCamera(this.preset);

  final ResolutionPreset preset;
  late final CameraController _controller;

  @override
  Future<Map<String, Object?>> open() async {
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    _controller = CameraController(
      back,
      preset,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller.initialize();
    final size = _controller.value.previewSize;
    return {
      'camera': back.name,
      'sensorOrientation': back.sensorOrientation,
      'preset': preset.name,
      'previewSize': '${size?.width.toInt()}x${size?.height.toInt()}',
    };
  }

  @override
  Widget preview() => CameraPreview(_controller);

  @override
  Future<void> startStream(FrameHandler onFrame) =>
      _controller.startImageStream((image) {
        final y = image.planes.first;
        onFrame(y.bytes, image.width, image.height, y.bytesPerRow, null);
      });

  @override
  Future<void> stopStream() => _controller.stopImageStream();

  @override
  Future<String> takePicture() async => (await _controller.takePicture()).path;

  @override
  Future<String> focus(double x, double y) async {
    await _controller.setFocusPoint(Offset(x, y));
    return 'requested';
  }

  @override
  Future<void> torch(bool on) =>
      _controller.setFlashMode(on ? FlashMode.torch : FlashMode.off);

  @override
  Future<void> lockExposure(bool locked) => _controller.setExposureMode(
    locked ? ExposureMode.locked : ExposureMode.auto,
  );

  @override
  Future<void> close() => _controller.dispose();
}
