import 'dart:typed_data';

import 'package:flutter/widgets.dart';

typedef FrameHandler = void Function(
  Uint8List y,
  int width,
  int height,
  int rowStride,
  int? nativeStampUs,
);

abstract interface class ProbeCamera {
  Future<Map<String, Object?>> open();
  Widget preview();
  Future<void> startStream(FrameHandler onFrame);
  Future<void> stopStream();
  Future<String> takePicture();
  Future<String> focus(double x, double y);
  Future<void> torch(bool on);
  Future<void> lockExposure(bool locked);
  Future<void> close();
}
