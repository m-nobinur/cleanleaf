import '../../../core/platform/ocr_api.g.dart';
import '../domain/ocr_engine.dart';
import '../domain/ocr_language.dart';

class PigeonOcrEngine implements OcrEngine {
  PigeonOcrEngine([OcrHostApi? api]) : _api = api ?? OcrHostApi();

  final OcrHostApi _api;

  @override
  Future<RecognizedPage?> recognize(
    String imagePath,
    OcrLanguage language,
  ) async {
    final page = await _api.recognize(imagePath, language.code, 0);
    return page == null ? null : (text: page.text, hocr: page.hocr);
  }

  @override
  Future<void> cancel() => _api.cancel();
}
