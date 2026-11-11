import 'dart:io';

import 'package:path/path.dart' as p;

import '../../library/domain/document_repository.dart';
import '../../library/domain/page_repository.dart';
import 'pdf_file_name.dart';

/// Copies each page image (render, else original) to a file named after the
/// document, because every page's stored files share one basename and the
/// share sheet keys its cache by basename.
class ExportJpg {
  ExportJpg({
    required this.documents,
    required this.pages,
    required this.resolve,
    required this.outputDir,
  });

  final DocumentRepository documents;
  final PageRepository pages;
  final Future<File> Function(String relativePath) resolve;
  final Future<Directory> Function() outputDir;

  Future<List<File>> call(String documentId) async {
    final document = await documents.get(documentId);
    if (document == null) throw StateError('No document $documentId');
    final docPages = await pages.getByDocument(documentId);
    if (docPages.isEmpty) throw StateError('Document $documentId has no pages');

    final dir = Directory(p.join((await outputDir()).path, documentId, 'jpg'));
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final base = pdfFileName(document.title);
    final width = docPages.length.toString().length.clamp(2, 4);
    return [
      for (final (i, page) in docPages.indexed)
        await (await resolve(page.renderPath ?? page.originalPath)).copy(
          p.join(
            dir.path,
            docPages.length == 1
                ? '$base.jpg'
                : '$base-${'${i + 1}'.padLeft(width, '0')}.jpg',
          ),
        ),
    ];
  }
}
