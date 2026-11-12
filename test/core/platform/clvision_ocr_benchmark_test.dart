// The benchmark prints its report to the test log.
// ignore_for_file: avoid_print
@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'clvision_ocr.dart';

// T-038: the bundled PP-OCR over a page set, writing T-032's scorer format:
//   CLEANLEAF_OCR_PAGES=<dir of .jpg> CLEANLEAF_OCR_OUT=<dir> [CLEANLEAF_FP16=0]
//   [CLEANLEAF_STOP_NON_LATIN=1] (Auto's early stop)
//   flutter test --tags benchmark test/core/platform/clvision_ocr_benchmark_test.dart

void main() {
  final env = Platform.environment;
  final pages = env['CLEANLEAF_OCR_PAGES'];
  final out = env['CLEANLEAF_OCR_OUT'];

  test(
    'reads the page set',
    () {
      final watch = Stopwatch()..start();
      final ocr = HostPpOcr(fp16: env['CLEANLEAF_FP16'] != '0');
      print('create ${watch.elapsedMilliseconds} ms');
      Directory(out!).createSync(recursive: true);
      final files =
          Directory(pages!)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.jpg'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        watch.reset();
        final page = ocr.read(
          file.readAsBytesSync(),
          stopIfNonLatin: env['CLEANLEAF_STOP_NON_LATIN'] == '1',
        );
        final ms = watch.elapsedMilliseconds;
        page['native'] = page['text'];
        final id = file.uri.pathSegments.last.replaceAll('.jpg', '');
        File('$out/$id.json').writeAsStringSync(jsonEncode(page));
        print(
          '$id ${(page['lines'] as List).length} lines $ms ms '
          'flagged ${page['flagged']} ${page['stages']}',
        );
      }
      ocr.dispose();
    },
    skip: pages == null || out == null
        ? 'set CLEANLEAF_OCR_PAGES and CLEANLEAF_OCR_OUT'
        : false,
  );
}
