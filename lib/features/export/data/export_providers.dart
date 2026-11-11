import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/storage_providers.dart';
import '../../library/data/library_providers.dart';
import '../domain/export_jpg.dart';
import '../domain/export_pdf.dart';
import 'pdf_isolate_builder.dart';

Future<Directory> _exportDir() async =>
    Directory(p.join((await getTemporaryDirectory()).path, 'export'));

final exportPdfProvider = Provider<ExportPdf>(
  (ref) => ExportPdf(
    documents: ref.watch(documentRepositoryProvider),
    pages: ref.watch(pageRepositoryProvider),
    resolve: ref.watch(fileStoreProvider).resolve,
    outputDir: _exportDir,
    build: buildPdfInIsolate,
  ),
);

final exportJpgProvider = Provider<ExportJpg>(
  (ref) => ExportJpg(
    documents: ref.watch(documentRepositoryProvider),
    pages: ref.watch(pageRepositoryProvider),
    resolve: ref.watch(fileStoreProvider).resolve,
    outputDir: _exportDir,
  ),
);

/// Exports the document to PDF in the app cache, then opens the share sheet.
final shareDocumentPdfProvider =
    Provider<
      Future<void> Function(String documentId, {ExportProgress? onProgress})
    >(
      (ref) => (documentId, {onProgress}) async {
        final file = await ref.read(exportPdfProvider)(
          documentId,
          onProgress: onProgress,
        );
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/pdf')],
            fileNameOverrides: [p.basename(file.path)],
          ),
        );
      },
    );

/// Copies the page images to named JPGs in the app cache, then shares them all.
final shareDocumentJpgProvider = Provider<Future<void> Function(String)>(
  (ref) => (documentId) async {
    final files = await ref.read(exportJpgProvider)(documentId);
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final f in files) XFile(f.path, mimeType: 'image/jpeg')],
      ),
    );
  },
);
