import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';
import '../../library/data/library_providers.dart';
import '../data/google_scan.dart';
import '../data/google_scanner_api.g.dart';
import '../domain/scan_engine.dart';

final scanEngineProvider =
    AsyncNotifierProvider<ScanEngineNotifier, ScanEngine>(
      ScanEngineNotifier.new,
    );

class ScanEngineNotifier extends AsyncNotifier<ScanEngine> {
  static const _key = 'scanEngine';

  @override
  Future<ScanEngine> build() async {
    final stored = await ref.watch(settingsStoreProvider).read(_key);
    return ScanEngine.values.asNameMap()[stored] ?? ScanEngine.cleanleaf;
  }

  Future<void> select(ScanEngine engine) async {
    state = AsyncData(engine);
    await ref.read(settingsStoreProvider).write(_key, engine.name);
  }
}

final _googleScannerApiProvider = Provider((_) => GoogleScannerHostApi());

/// Only the engine picker reads this, so Play Services is never queried
/// unless the user opens it.
final googleScannerAvailableProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(_googleScannerApiProvider).isAvailable(),
);

final googleScanProvider = Provider(
  (ref) => GoogleScan(
    scan: ref.watch(_googleScannerApiProvider).scan,
    documents: ref.watch(documentRepositoryProvider),
    pages: ref.watch(pageRepositoryProvider),
  ),
);
