import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';
import '../data/library_providers.dart';
import '../domain/document.dart';
import '../domain/document_page.dart';

final documentsProvider = StreamProvider<List<Document>>(
  (ref) => ref.watch(documentRepositoryProvider).watchAll(),
);

final documentPagesProvider = StreamProvider.family<List<DocumentPage>, String>(
  (ref, documentId) =>
      ref.watch(pageRepositoryProvider).watchByDocument(documentId),
);

final thumbFileProvider = FutureProvider.family<File, String>(
  (ref, relativePath) => ref.watch(fileStoreProvider).resolve(relativePath),
);
