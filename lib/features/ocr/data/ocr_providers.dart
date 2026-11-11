import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';
import '../domain/ocr_engine.dart';
import '../domain/ocr_repository.dart';
import 'drift_ocr_repository.dart';
import 'ocr_queue.dart';
import 'pigeon_ocr_engine.dart';

// Interim: Tesseract for both languages until T-032 picks the English engine.
final ocrEngineProvider = Provider<OcrEngine>(
  (ref) => PigeonOcrEngine('tesseract'),
);

/// Started once by main(); reads pending pages in the background.
final ocrQueueProvider = Provider<OcrQueue>((ref) {
  final queue = OcrQueue(
    ref.watch(appDatabaseProvider),
    ref.watch(fileStoreProvider),
    ref.watch(ocrEngineProvider),
  );
  ref.onDispose(queue.stop);
  return queue;
});

final ocrRepositoryProvider = Provider<OcrRepository>(
  (ref) => DriftOcrRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(ocrQueueProvider),
  ),
);
