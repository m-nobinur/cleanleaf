import 'dart:convert';

import '../../../core/storage/app_database.dart';
import '../domain/ocr_language.dart';
import '../domain/ocr_result.dart';

String encodeOcrWords(List<OcrWord> words) => jsonEncode([
  for (final w in words)
    {
      'text': w.text,
      'box': [w.left, w.top, w.right, w.bottom],
      'conf': w.confidence,
    },
]);

List<OcrWord> decodeOcrWords(String json) => [
  for (final w
      in (jsonDecode(json) as List<Object?>).cast<Map<String, Object?>>())
    if ((w['box']! as List<Object?>).cast<num>() case [
      final left,
      final top,
      final right,
      final bottom,
    ])
      OcrWord(
        w['text']! as String,
        left: left.toDouble(),
        top: top.toDouble(),
        right: right.toDouble(),
        bottom: bottom.toDouble(),
        confidence: w['conf']! as int,
      ),
];

// Background reads have no language set and use auto.
OcrLanguage ocrLanguageOf(PageRow r) => r.ocrLanguage == null
    ? OcrLanguage.auto
    : OcrLanguage.values.byName(r.ocrLanguage!);
