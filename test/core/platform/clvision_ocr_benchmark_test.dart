// The benchmark prints its report to the test log.
// ignore_for_file: avoid_print
@Tags(['benchmark'])
@DefaultAsset('package:cleanleaf/core/platform/clvision.dart')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cleanleaf/core/platform/clvision.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

// T-038 phase A: PP-OCR in clvision over a page set, writing T-032's scorer
// format. Models come from .local/models/ppocr (not shipped yet):
//   CLEANLEAF_PPOCR_MODELS=<dir> CLEANLEAF_OCR_PAGES=<dir> CLEANLEAF_OCR_OUT=<dir>
//   [CLEANLEAF_FP16=0] [CLEANLEAF_PPOCR_RECS=a.tflite,b.tflite]
//   flutter test --tags benchmark test/core/platform/clvision_ocr_benchmark_test.dart

final class _ClvOcr extends Opaque {}

@Native<
  Pointer<_ClvOcr> Function(
    Pointer<Uint8>,
    Int32,
    Pointer<Pointer<Uint8>>,
    Pointer<Int32>,
    Int32,
    Pointer<Uint8>,
    Int32,
    Int32,
    Int32,
  )
>(symbol: 'clv_ocr_create')
external Pointer<_ClvOcr> _create(
  Pointer<Uint8> det,
  int detLength,
  Pointer<Pointer<Uint8>> recs,
  Pointer<Int32> recLengths,
  int recCount,
  Pointer<Uint8> dict,
  int dictLength,
  int fp16,
  int threads,
);

@Native<Void Function(Pointer<_ClvOcr>)>(symbol: 'clv_ocr_destroy')
external void _destroy(Pointer<_ClvOcr> ocr);

@Native<
  Int32 Function(
    Pointer<_ClvOcr>,
    Pointer<Uint8>,
    Int32,
    Pointer<Pointer<Uint8>>,
    Pointer<Int32>,
  )
>(symbol: 'clv_ocr_read')
external int _read(
  Pointer<_ClvOcr> ocr,
  Pointer<Uint8> encoded,
  int length,
  Pointer<Pointer<Uint8>> jsonOut,
  Pointer<Int32> jsonLengthOut,
);

Pointer<Uint8> _copy(List<int> bytes) =>
    malloc<Uint8>(bytes.length)..asTypedList(bytes.length).setAll(0, bytes);

void main() {
  final env = Platform.environment;
  final models = env['CLEANLEAF_PPOCR_MODELS'];
  final pages = env['CLEANLEAF_OCR_PAGES'];
  final out = env['CLEANLEAF_OCR_OUT'];

  test(
    'reads the page set',
    () {
      final fp16 = env['CLEANLEAF_FP16'] != '0';
      final recNames =
          (env['CLEANLEAF_PPOCR_RECS'] ??
                  'ppocr_v6s_rec_latin_dynw_fp16w.tflite')
              .split(',');
      final det = File('$models/ppocr_v6s_det960_fp16w.tflite')
          .readAsBytesSync();
      final recs = [
        for (final name in recNames) File('$models/$name').readAsBytesSync(),
      ];
      final classes = (jsonDecode(
        File('$models/ppocr_v6s_rec_latin_dict.json').readAsStringSync(),
      ) as List).cast<String>();
      final dict = utf8.encode(classes.join('\n'));
      final detPtr = _copy(det);
      final recPtrs = malloc<Pointer<Uint8>>(recs.length);
      final recLengths = malloc<Int32>(recs.length);
      for (var i = 0; i < recs.length; i++) {
        recPtrs[i] = _copy(recs[i]);
        recLengths[i] = recs[i].length;
      }
      final dictPtr = _copy(dict);
      final watch = Stopwatch()..start();
      final ocr = _create(
        detPtr,
        det.length,
        recPtrs,
        recLengths,
        recs.length,
        dictPtr,
        dict.length,
        fp16 ? 1 : 0,
        4,
      );
      print('create ${watch.elapsedMilliseconds} ms fp16=$fp16 recs=$recNames');
      expect(ocr, isNot(nullptr));
      Directory(out!).createSync(recursive: true);
      final files =
          Directory(pages!)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.jpg'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final bytes = file.readAsBytesSync();
        using((arena) {
          final input = arena<Uint8>(bytes.length)
            ..asTypedList(bytes.length).setAll(0, bytes);
          final json = arena<Pointer<Uint8>>();
          final length = arena<Int32>();
          watch.reset();
          expect(_read(ocr, input, bytes.length, json, length), ClvStatus.ok);
          final ms = watch.elapsedMilliseconds;
          final page = jsonDecode(
            utf8.decode(json.value.asTypedList(length.value)),
          ) as Map<String, dynamic>;
          clvFree(json.value.cast());
          final lines = (page['lines'] as List).cast<Map<String, dynamic>>();
          page['native'] = lines.map((l) => l['text']).join('\n');
          final id = file.uri.pathSegments.last.replaceAll('.jpg', '');
          File('$out/$id.json').writeAsStringSync(jsonEncode(page));
          print('$id ${lines.length} lines $ms ms ${page['stages']}');
        });
      }
      _destroy(ocr);
      for (var i = 0; i < recs.length; i++) {
        malloc.free(recPtrs[i]);
      }
      malloc
        ..free(recPtrs)
        ..free(recLengths)
        ..free(detPtr)
        ..free(dictPtr);
    },
    skip: models == null || pages == null || out == null
        ? 'set CLEANLEAF_PPOCR_MODELS, CLEANLEAF_OCR_PAGES, CLEANLEAF_OCR_OUT'
        : false,
  );
}
