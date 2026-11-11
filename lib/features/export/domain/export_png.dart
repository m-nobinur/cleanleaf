import 'dart:io';

import '../../enhance/domain/page_renderer.dart';
import '../../library/domain/document_repository.dart';
import '../../library/domain/page_repository.dart';
import 'export_jpg.dart';

/// Renders each page afresh from its original as lossless PNG, with the
/// page's saved crop, rotation, filter and adjustments; the stored render is
/// JPEG and would carry its artefacts into the PNG.
class ExportPng {
  ExportPng({
    required this.documents,
    required this.pages,
    required this.resolve,
    required this.outputDir,
    required this.renderer,
  });

  final DocumentRepository documents;
  final PageRepository pages;
  final Future<File> Function(String relativePath) resolve;
  final Future<Directory> Function() outputDir;
  final PageRenderer renderer;

  Future<List<File>> call(String documentId) => exportPageImages(
    documents: documents,
    pages: pages,
    outputDir: outputDir,
    documentId: documentId,
    extension: 'png',
    write: (page, path) async {
      final png = await renderer.render(
        (await resolve(page.originalPath)).path,
        page.corners,
        page.rotation,
        page.filter,
        page.filterParams,
        png: true,
      );
      return File(path).writeAsBytes(png, flush: true);
    },
  );
}
