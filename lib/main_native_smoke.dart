import 'package:flutter/widgets.dart';

import 'core/platform/camera_api.g.dart';
import 'core/platform/clvision.dart';
import 'core/platform/vision_api.g.dart';

// Device smoke test for the native stack: run with -t and read
// `adb logcat -s flutter:I` until `CLBENCH DONE`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _step('version', () async => openCvVersion());
  await _step('jni', VisionHostApi().opencvVersion);
  await _step('camera', () async {
    final caps = await CameraHostApi().capabilities();
    if (caps == null) return 'no back camera';
    return '${caps.sensorWidth}x${caps.sensorHeight} '
        'level=${caps.hardwareLevel.name} torch=${caps.hasTorch} '
        'orientation=${caps.sensorOrientation}';
  });
  debugPrint('CLBENCH DONE');
  runApp(const SizedBox.shrink());
}

Future<void> _step(String name, Future<String> Function() run) async {
  try {
    debugPrint('CLBENCH $name ${await run()}');
  } catch (e) {
    debugPrint('CLBENCH $name FAILED $e');
  }
}
