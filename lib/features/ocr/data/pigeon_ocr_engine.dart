import 'dart:isolate';

import '../../../core/platform/ocr_api.g.dart';
import '../domain/ocr_engine.dart';
import '../domain/ocr_language.dart';
import '../domain/ocr_result.dart';
import 'hocr_parser.dart';

/// A native engine behind `OcrHostApi`, chosen by [engine] (e.g. `tesseract`).
class PigeonOcrEngine implements OcrEngine {
  PigeonOcrEngine(this.engine, [OcrHostApi? api]) : _api = api ?? OcrHostApi();

  final String engine;
  final OcrHostApi _api;

  @override
  Future<OcrResult?> recognize(String imagePath, OcrLanguage language) async {
    final page = await _api.recognize(engine, imagePath, language.name, 0);
    if (page == null) return null;
    return OcrResult(
      page.text,
      lines: await _parse(page.hocr),
      engine: engine,
      language: language,
    );
  }

  @override
  Future<void> cancel() => _api.cancel();
}

// Top level so the isolate closure captures only [hocr].
Future<List<OcrLine>> _parse(String hocr) =>
    Isolate.run(() => parseHocrLines(hocr));
