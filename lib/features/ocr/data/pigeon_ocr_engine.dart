import 'dart:isolate';

import '../../../core/platform/ocr_api.g.dart';
import '../domain/ocr_engine.dart';
import '../domain/ocr_language.dart';
import '../domain/ocr_result.dart';
import 'hocr_parser.dart';

const ppOcrEngine = 'ppocr';
const tesseractEngine = 'tesseract';

/// PP-OCR reads English and Auto, Tesseract eng+ben reads Bangla
/// (decisions.md D-64).
String ocrEngineFor(OcrLanguage language) =>
    language == OcrLanguage.bangla ? tesseractEngine : ppOcrEngine;

/// The native engines behind `OcrHostApi`, picked per language by
/// [engineFor]. Auto re-reads a page PP-OCR flags as non-Latin with Tesseract
/// eng+ben (decisions.md D-59).
class PigeonOcrEngine implements OcrEngine {
  PigeonOcrEngine({this.engineFor = ocrEngineFor, OcrHostApi? api})
    : _api = api ?? OcrHostApi();

  final String Function(OcrLanguage language) engineFor;
  final OcrHostApi _api;
  bool _cancelled = false;

  @override
  Future<OcrResult?> recognize(String imagePath, OcrLanguage language) async {
    _cancelled = false;
    var engine = engineFor(language);
    var page = await _api.recognize(engine, imagePath, language.name, 0);
    if (language == OcrLanguage.auto && page?.nonLatin == true) {
      // The host forgets a cancel that lands between its two reads.
      if (_cancelled) return null;
      engine = tesseractEngine;
      page = await _api.recognize(engine, imagePath, language.name, 0);
    }
    if (page == null) return null;
    return OcrResult(
      page.text,
      lines: await _parse(page.hocr),
      engine: engine,
      language: language,
    );
  }

  @override
  Future<void> cancel() {
    _cancelled = true;
    return _api.cancel();
  }

  @override
  Future<void> release() => _api.release();
}

// Top level so the isolate closure captures only [hocr].
Future<List<OcrLine>> _parse(String hocr) =>
    Isolate.run(() => parseHocrLines(hocr));
