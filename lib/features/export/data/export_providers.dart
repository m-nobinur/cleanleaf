import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/storage_providers.dart';
import '../../enhance/data/enhance_providers.dart';
import '../../library/data/library_providers.dart';
import '../../ocr/data/ocr_providers.dart';
import '../domain/export_jpg.dart';
import '../domain/export_pdf.dart';
import '../domain/export_png.dart';
import '../domain/export_text.dart';
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

final exportPngProvider = Provider<ExportPng>(
  (ref) => ExportPng(
    documents: ref.watch(documentRepositoryProvider),
    pages: ref.watch(pageRepositoryProvider),
    resolve: ref.watch(fileStoreProvider).resolve,
    outputDir: _exportDir,
    renderer: ref.watch(pageRendererProvider),
  ),
);

final exportTextProvider = Provider<ExportText>(
  (ref) => ExportText(
    documents: ref.watch(documentRepositoryProvider),
    pages: ref.watch(pageRepositoryProvider),
    ocr: ref.watch(ocrRepositoryProvider),
    resolve: ref.watch(fileStoreProvider).resolve,
    outputDir: _exportDir,
    buildSearchablePdf: (images, texts) async {
      final font = await rootBundle.load(
        'assets/fonts/NotoSansBengali-Regular-subset.ttf',
      );
      return buildSearchablePdfInIsolate(
        images,
        texts,
        font.buffer.asUint8List(font.offsetInBytes, font.lengthInBytes),
      );
    },
  ),
);

typedef ShareTextExport = Future<void> Function(
  String documentId, {
  ExportProgress? onProgress,
});

Future<void> _shareFile(File file, String mimeType) => SharePlus.instance.share(
  ShareParams(
    files: [XFile(file.path, mimeType: mimeType)],
    fileNameOverrides: [p.basename(file.path)],
  ),
);

/// Reads any unread pages, writes the text as .txt, then shares it.
final shareDocumentTxtProvider = Provider<ShareTextExport>(
  (ref) =>
      (documentId, {onProgress}) async => _shareFile(
        await ref
            .read(exportTextProvider)
            .txt(documentId, onProgress: onProgress),
        'text/plain',
      ),
);

final shareDocumentDocxProvider = Provider<ShareTextExport>(
  (ref) =>
      (documentId, {onProgress}) async => _shareFile(
        await ref
            .read(exportTextProvider)
            .docx(documentId, onProgress: onProgress),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      ),
);

final shareDocumentSearchablePdfProvider = Provider<ShareTextExport>(
  (ref) =>
      (documentId, {onProgress}) async => _shareFile(
        await ref
            .read(exportTextProvider)
            .searchablePdf(documentId, onProgress: onProgress),
        'application/pdf',
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

/// Renders the pages as named PNGs in the app cache, then shares them all.
final shareDocumentPngProvider = Provider<Future<void> Function(String)>(
  (ref) => (documentId) async {
    final files = await ref.read(exportPngProvider)(documentId);
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final f in files) XFile(f.path, mimeType: 'image/png')],
      ),
    );
  },
);
