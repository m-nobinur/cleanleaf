import 'ocr_language.dart';

// Box edges are normalized 0..1 to the image that was read (the page render).

class OcrWord(
  final String text, {
  required final double left,
  required final double top,
  required final double right,
  required final double bottom,
  required final int confidence,
});

class OcrLine(
  final List<OcrWord> words, {
  required final double left,
  required final double top,
  required final double right,
  required final double bottom,
});

/// [engine] names the engine that produced it, e.g. `tesseract`.
class OcrResult(
  final String text, {
  required final List<OcrLine> lines,
  required final String engine,
  required final OcrLanguage language,
});
