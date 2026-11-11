import 'dart:async';

import 'package:cleanleaf/core/platform/camera_api.g.dart';
import 'package:cleanleaf/features/capture/data/pigeon_document_camera.dart';
import 'package:cleanleaf/features/capture/domain/document_camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHost extends CameraHostApi {
  _FakeHost({this.handlesCropAndRotation = false});

  final bool handlesCropAndRotation;

  @override
  Future<CameraPermissionStatus> requestPermission() async =>
      CameraPermissionStatus.permanentlyDenied;

  @override
  Future<CameraSession> start() async => CameraSession(
    textureId: 7,
    previewWidth: 1600,
    previewHeight: 1200,
    analysisWidth: 640,
    analysisHeight: 480,
    captureWidth: 4064,
    captureHeight: 3048,
    sensorRotation: 90,
    handlesCropAndRotation: handlesCropAndRotation,
  );

  @override
  Future<CameraCapabilities?> capabilities() async => CameraCapabilities(
    sensorWidth: 4080,
    sensorHeight: 3072,
    hardwareLevel: CameraHardwareLevel.full,
    hasTorch: true,
    sensorOrientation: 90,
  );

  @override
  Future<String> capture() =>
      Future.error(PlatformException(code: 'notStarted'));

  @override
  Future<void> setTorch(bool enabled) =>
      Future.error(PlatformException(code: 'IllegalStateException'));
}

void main() {
  test(
    'start reports the upright preview and the turns Flutter applies',
    () async {
      final preview = await PigeonDocumentCamera(
        host: _FakeHost(),
        frames: const Stream.empty(),
      ).start();

      expect(preview, (
        textureId: 7,
        width: 1200,
        height: 1600,
        quarterTurns: 1,
        hasTorch: true,
      ));

      final rotated = await PigeonDocumentCamera(
        host: _FakeHost(handlesCropAndRotation: true),
        frames: const Stream.empty(),
      ).start();
      expect(
        (rotated.width, rotated.height, rotated.quarterTurns),
        (1200, 1600, 0),
      );
    },
  );

  test('platform error codes become camera failures', () async {
    final camera = PigeonDocumentCamera(
      host: _FakeHost(),
      frames: const Stream.empty(),
    );

    await expectLater(camera.capture(), throwsA(CameraFailure.notStarted));
    await expectLater(
      camera.setTorch(true),
      throwsA(CameraFailure.unavailable),
    );
    expect(
      await camera.requestPermission(),
      CameraPermission.permanentlyDenied,
    );
  });

  test('corner frames map to quads, and stream errors to failures', () async {
    final frames = StreamController<CornerFrame>();
    final camera = PigeonDocumentCamera(
      host: _FakeHost(),
      frames: frames.stream,
    );
    final events = <Object>[];
    final done = Completer<void>();
    camera.detections.listen(
      events.add,
      onError: events.add,
      onDone: done.complete,
    );

    frames
      ..add(
        CornerFrame(
          corners: [0.1, 0.2, 0.9, 0.2, 0.9, 0.8, 0.1, 0.8],
          confidence: 0.9,
          isStable: true,
          timestampUs: 1,
        ),
      )
      ..add(
        CornerFrame(
          corners: null,
          confidence: 0,
          isStable: false,
          timestampUs: 2,
        ),
      )
      ..addError(PlatformException(code: 'inUse'));
    await frames.close();
    await done.future;

    expect(events, [
      (
        quad: (
          topLeft: (x: 0.1, y: 0.2),
          topRight: (x: 0.9, y: 0.2),
          bottomRight: (x: 0.9, y: 0.8),
          bottomLeft: (x: 0.1, y: 0.8),
        ),
        confidence: 0.9,
        isStable: true,
      ),
      (quad: null, confidence: 0.0, isStable: false),
      CameraFailure.inUse,
    ]);
  });
}
