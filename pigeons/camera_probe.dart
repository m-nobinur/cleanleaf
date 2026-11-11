import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/spike/camera_probe_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/bnwise/cleanleaf/camera/CameraProbeApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.bnwise.cleanleaf.camera'),
  ),
)
class CameraInfoMsg {
  CameraInfoMsg({
    required this.textureId,
    required this.previewWidth,
    required this.previewHeight,
    required this.analysisWidth,
    required this.analysisHeight,
    required this.captureWidth,
    required this.captureHeight,
    required this.handlesCropAndRotation,
    required this.sensorRotation,
    required this.details,
  });

  int textureId;
  int previewWidth;
  int previewHeight;
  int analysisWidth;
  int analysisHeight;
  int captureWidth;
  int captureHeight;
  bool handlesCropAndRotation;
  int sensorRotation;
  String details;
}

class FrameMsg {
  FrameMsg({
    required this.y,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.stampUs,
  });

  Uint8List y;
  int width;
  int height;
  int rowStride;
  int stampUs;
}

@HostApi()
abstract class CameraProbeHostApi {
  @async
  CameraInfoMsg open(int analysisWidth, int analysisHeight, int fps);
  void startStream();
  void stopStream();
  @async
  String takePicture();
  @async
  String focus(double x, double y);
  @async
  void torch(bool on);
  @async
  void lockExposure(bool locked);
  int monotonicNowUs();
  String stats();
  void close();
}

@EventChannelApi()
abstract class CameraProbeEvents {
  FrameMsg frames();
}
