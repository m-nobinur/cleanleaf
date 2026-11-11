import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/camera_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/bnwise/cleanleaf/camera/CameraApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.bnwise.cleanleaf.camera'),
  ),
)
enum CameraPermissionStatus { granted, denied, permanentlyDenied }

enum CameraHardwareLevel { legacy, limited, full, level3, external }

class CameraCapabilities {
  CameraCapabilities({
    required this.sensorWidth,
    required this.sensorHeight,
    required this.hardwareLevel,
    required this.hasTorch,
    required this.sensorOrientation,
  });

  int sensorWidth;
  int sensorHeight;
  CameraHardwareLevel hardwareLevel;
  bool hasTorch;
  int sensorOrientation;
}

class CameraSession {
  CameraSession({
    required this.textureId,
    required this.previewWidth,
    required this.previewHeight,
    required this.analysisWidth,
    required this.analysisHeight,
    required this.captureWidth,
    required this.captureHeight,
    required this.sensorRotation,
    required this.handlesCropAndRotation,
  });

  int textureId;
  int previewWidth;
  int previewHeight;
  int analysisWidth;
  int analysisHeight;
  int captureWidth;
  int captureHeight;
  int sensorRotation;

  /// When false, Dart rotates the preview texture by [sensorRotation].
  bool handlesCropAndRotation;
}

/// Detection result for one analysis frame. Pixels never cross the bridge.
class CornerFrame {
  CornerFrame({
    required this.corners,
    required this.confidence,
    required this.isStable,
    required this.timestampUs,
  });

  /// TL, TR, BR, BL (x, y) normalized to the upright frame; null when no page.
  List<double>? corners;
  double confidence;
  bool isStable;
  int timestampUs;
}

@HostApi()
abstract class CameraHostApi {
  @async
  CameraPermissionStatus requestPermission();

  void openAppSettings();

  /// Back camera characteristics; null when the device has none.
  CameraCapabilities? capabilities();

  @async
  CameraSession start();

  void stop();

  /// Full-resolution still; returns the JPEG file path.
  @async
  String capture();

  @async
  void setTorch(bool enabled);

  /// [x] and [y] are normalized preview coordinates; true when focus locked.
  @async
  bool focusAt(double x, double y);
}

@EventChannelApi()
abstract class CameraEventApi {
  CornerFrame cornerFrames();
}
