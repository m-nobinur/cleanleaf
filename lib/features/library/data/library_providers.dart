import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/metrics/ab_session.dart';
import '../../../core/storage/storage_providers.dart';
import '../domain/document_repository.dart';
import '../domain/page_repository.dart';
import 'ab_recording_page_repository.dart';
import 'drift_document_repository.dart';
import 'drift_page_repository.dart';

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DriftDocumentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(fileStoreProvider),
  ),
);

final pageRepositoryProvider = Provider<PageRepository>((ref) {
  final files = ref.watch(fileStoreProvider);
  final pages = DriftPageRepository(ref.watch(appDatabaseProvider), files);
  final ab = AbSession.current;
  return ab == null ? pages : AbRecordingPageRepository(pages, files, ab);
});
