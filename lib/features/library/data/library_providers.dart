import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';
import '../domain/document_repository.dart';
import '../domain/page_repository.dart';
import 'drift_document_repository.dart';
import 'drift_page_repository.dart';

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DriftDocumentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(fileStoreProvider),
  ),
);

final pageRepositoryProvider = Provider<PageRepository>(
  (ref) => DriftPageRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(fileStoreProvider),
  ),
);
