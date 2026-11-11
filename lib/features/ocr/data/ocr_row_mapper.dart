import 'dart:convert';

import '../../../core/storage/app_database.dart';
import '../domain/ocr_language.dart';
import '../domain/ocr_result.dart';

List<double> _box(double l, double t, double r, double b) => [l, t, r, b];

String encodeOcrLines(List<OcrLine> lines) => jsonEncode([
  for (final line in lines)
    {
      'box': _box(line.left, line.top, line.right, line.bottom),
      'words': [
        for (final w in line.words)
          {
            'text': w.text,
            'box': _box(w.left, w.top, w.right, w.bottom),
            'conf': w.confidence,
          },
      ],
    },
]);

List<OcrLine> decodeOcrLines(String json) => [
  for (final line
      in (jsonDecode(json) as List<Object?>).cast<Map<String, Object?>>())
    if (_parseBox(line['box']) case (final l, final t, final r, final b))
      OcrLine(
        [
          for (final w
              in (line['words']! as List<Object?>).cast<Map<String, Object?>>())
            if (_parseBox(w['box']) case (final l, final t, final r, final b))
              OcrWord(
                w['text']! as String,
                left: l,
                top: t,
                right: r,
                bottom: b,
                confidence: w['conf']! as int,
              ),
        ],
        left: l,
        top: t,
        right: r,
        bottom: b,
      ),
];

(double, double, double, double) _parseBox(Object? json) {
  final [l, t, r, b] = (json! as List<Object?>).cast<num>();
  return (l.toDouble(), t.toDouble(), r.toDouble(), b.toDouble());
}

// Background reads have no language set and use auto.
OcrLanguage ocrLanguageOf(PageRow r) => r.ocrLanguage == null
    ? OcrLanguage.auto
    : OcrLanguage.values.byName(r.ocrLanguage!);

OcrResult ocrResultOf(PageRow r) => OcrResult(
  r.ocrText ?? '',
  lines: decodeOcrLines(r.ocrLines ?? '[]'),
  engine: r.ocrEngine ?? '',
  language: ocrLanguageOf(r),
);
