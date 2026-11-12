import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'core/platform/ocr_bench_api.g.dart';

// T-038 probe: PP-OCR in clvision on the phone. Run with -t and
// --android-project-arg=probe=true. The app creates <external files>/ocr-bench/
// pages and models (a dir adb creates is unreadable to the app) and waits up to
// 10 min for go.json, pushed last. Kotlin (ocrbench/) logs `CLBENCH` lines;
// read `adb logcat -s CLBENCH:I flutter:I tflite:I` until `CLBENCH DONE`, then
// pull ocr-bench/out/ and ocr-bench/summary.jsonl.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final dir = Directory(
    '${(await getExternalStorageDirectory())!.path}/ocr-bench',
  )..createSync();
  for (final sub in const ['pages', 'models']) {
    Directory('${dir.path}/$sub').createSync(recursive: true);
  }
  debugPrint('CLBENCH waiting for inputs in ${dir.path}');
  try {
    final go = File('${dir.path}/go.json');
    for (var i = 0; i < 600 && !go.existsSync(); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    debugPrint('CLBENCH summary ${await OcrBenchHostApi().run(dir.path)}');
  } catch (e, stack) {
    debugPrint('CLBENCH FAILED $e $stack');
  } finally {
    debugPrint('CLBENCH DONE');
  }
}
