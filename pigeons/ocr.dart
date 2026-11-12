import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/ocr_api.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/bnwise/cleanleaf/ocr/OcrApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.bnwise.cleanleaf.ocr'),
  ),
)
/// Every engine answers in hOCR, so Dart has one parser for all of them.
class OcrPage {
  OcrPage({required this.text, required this.hocr, this.nonLatin});

  String text;
  String hocr;

  /// PP-OCR only: at least 25% of the line width read as unsure Latin
  /// (decisions.md D-59), so Auto re-reads the page with Tesseract. When the
  /// page was read in `auto`, PP-OCR stops as soon as it knows and the text is
  /// partial.
  bool? nonLatin;
}

@HostApi()
abstract class OcrHostApi {
  /// Reads the image with [engine] (e.g. `tesseract`) in [language] (an
  /// `OcrLanguage` name), downscaled to [maxLongSide] px first when > 0.
  /// Null when [cancel] stopped it.
  @async
  OcrPage? recognize(
    String engine,
    String imagePath,
    String language,
    int maxLongSide,
  );

  void cancel();

  /// Frees every engine's memory; the next [recognize] loads its engine again.
  @async
  void release();
}
