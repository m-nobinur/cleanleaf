import 'package:pigeon/pigeon.dart';

// Output stays inside the deletable scan_engine feature (decisions.md D-02a).
@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/features/scan_engine/data/google_scanner_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/bnwise/cleanleaf/mlkit/GoogleScannerApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.bnwise.cleanleaf.mlkit'),
  ),
)
@HostApi()
abstract class GoogleScannerHostApi {
  /// True when Google Play services can run the ML Kit document scanner.
  bool isAvailable();

  /// Runs Google's scanner UI. Returns a JPEG path in the app cache, or null
  /// when the user cancels.
  @async
  String? scan();
}
