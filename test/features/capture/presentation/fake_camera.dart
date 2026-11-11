import 'dart:async';

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/features/capture/domain/document_camera.dart';
import 'package:cleanleaf/features/capture/domain/scan_mode.dart';

class FakeCamera implements DocumentCamera {
  CameraPermission permission = CameraPermission.granted;
  CameraFailure? startFailure;
  final frames = StreamController<LiveDetection>.broadcast();
  int starts = 0;
  int stops = 0;
  int captures = 0;
  bool openedSettings = false;
  final torch = <bool>[];
  final focused = <Point>[];
  final codeFamilies = <CodeFamily?>[];
  final scannedCodes = StreamController<ScannedCode>.broadcast();
  final opened = <Uri>[];

  @override
  Future<CameraPermission> requestPermission() async => permission;

  @override
  Future<void> openAppSettings() async => openedSettings = true;

  @override
  Future<CameraPreview> start() async {
    starts++;
    if (permission != CameraPermission.granted) {
      throw CameraFailure.permissionDenied;
    }
    if (startFailure case final failure?) throw failure;
    return (
      textureId: starts,
      width: 300,
      height: 400,
      quarterTurns: 0,
      hasTorch: true,
    );
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<String> capture() async {
    captures++;
    return '/cache/capture/still$captures.jpg';
  }

  @override
  Future<void> setTorch(bool enabled) async => torch.add(enabled);

  @override
  Future<bool> focusAt(Point point) async {
    focused.add(point);
    return true;
  }

  @override
  Stream<LiveDetection> get detections => frames.stream;

  @override
  Future<void> readCodes(CodeFamily? family) async => codeFamilies.add(family);

  @override
  Stream<ScannedCode> get codes => scannedCodes.stream;

  @override
  Future<bool> openLink(Uri link) async {
    opened.add(link);
    return true;
  }
}
