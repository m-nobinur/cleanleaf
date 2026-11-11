import 'ocr_language.dart';

typedef RecognizedPage = ({String text, String hocr});

abstract interface class OcrEngine {
  /// Reads the image at the absolute [imagePath]; null when [cancel] stopped it.
  Future<RecognizedPage?> recognize(String imagePath, OcrLanguage language);

  /// Stops the recognition in progress, if any.
  Future<void> cancel();
}
