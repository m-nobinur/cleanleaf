import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../library/domain/document_page.dart';
import '../../library/domain/document_repository.dart';
import '../../library/domain/page_repository.dart';
import 'pdf_file_name.dart';

typedef ExportProgress = void Function(int done, int total);

/// Builds PDF bytes from image files, one page per path, in order.
typedef PdfBuilder = Future<Uint8List> Function(
  List<String> imagePaths,
  ExportProgress? onProgress,
);

class ExportPdf {
  ExportPdf({
    required this.documents,
    required this.pages,
    required this.resolve,
    required this.outputDir,
    required this.build,
  });

  final DocumentRepository documents;
  final PageRepository pages;
  final Future<File> Function(String relativePath) resolve;
  final Future<Directory> Function() outputDir;
  final PdfBuilder build;

  Future<File> call(String documentId, {ExportProgress? onProgress}) async {
    final document = await documents.get(documentId);
    if (document == null) throw StateError('No document $documentId');
    final docPages = await pages.getByDocument(documentId);
    if (docPages.isEmpty) throw StateError('Document $documentId has no pages');

    final paths = [
      for (final page in docPages) (await resolve(_imagePath(page))).path,
    ];
    final bytes = await build(paths, onProgress);

    // One folder per document so equal titles can't overwrite each other.
    final dir = Directory(p.join((await outputDir()).path, documentId));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${pdfFileName(document.title)}.pdf'));
    return file.writeAsBytes(bytes, flush: true);
  }

  // Phase 1 fallback: the original until the enhance step writes a render.
  String _imagePath(DocumentPage page) => page.renderPath ?? page.originalPath;
}
