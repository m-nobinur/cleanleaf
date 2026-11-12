import 'ocr_language.dart';
import 'ocr_result.dart';

/// The one OCR contract; engines are swapped behind it (decisions.md D-13a).
abstract interface class OcrEngine {
  /// Reads the image at the absolute [imagePath]; null when [cancel] stopped it.
  Future<OcrResult?> recognize(String imagePath, OcrLanguage language);

  /// Stops the recognition in progress, if any.
  Future<void> cancel();

  /// Frees the engine's memory; the next [recognize] loads it again.
  Future<void> release();
}
