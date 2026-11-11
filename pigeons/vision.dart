import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/vision_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/bnwise/cleanleaf/vision/VisionApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.bnwise.cleanleaf.vision'),
  ),
)
@HostApi()
abstract class VisionHostApi {
  /// OpenCV version reported by libclvision through JNI.
  String opencvVersion();
}
