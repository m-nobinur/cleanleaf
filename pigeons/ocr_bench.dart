import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/ocr_bench_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/bnwise/cleanleaf/ocrbench/OcrBenchApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.bnwise.cleanleaf.ocrbench'),
  ),
)
@HostApi()
abstract class OcrBenchHostApi {
  /// Runs the OCR phone benchmark described by `<dir>/go.json` (T-038);
  /// returns a one-line summary.
  @async
  String run(String dir);
}
