import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/ocr_api.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/bnwise/cleanleaf/ocr/OcrApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.bnwise.cleanleaf.ocr'),
  ),
)
class OcrPage {
  OcrPage({required this.text, required this.hocr});

  String text;
  String hocr;
}

@HostApi()
abstract class OcrHostApi {
  /// Reads the image with Tesseract [languages] (e.g. `eng+ben`), downscaled
  /// to [maxLongSide] px first when > 0. Null when [cancel] stopped it.
  @async
  OcrPage? recognize(String imagePath, String languages, int maxLongSide);

  void cancel();
}
