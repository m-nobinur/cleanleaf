import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../library/domain/document_page.dart';
import '../../library/domain/document_repository.dart';
import '../../library/domain/page_repository.dart';
import '../../ocr/domain/ocr_repository.dart';
import '../../ocr/domain/ocr_result.dart';
import 'docx.dart';
import 'export_pdf.dart';
import 'pdf_file_name.dart';
import 'plain_text.dart';

/// Builds PDF bytes from image files with an invisible text layer per page;
/// a null text leaves that page image-only.
typedef SearchablePdfBuilder = Future<Uint8List> Function(
  List<String> imagePaths,
  List<OcrResult?> texts,
);

/// Exports a document's recognised text as .txt, .docx or a searchable PDF.
/// Each page uses its stored text in whatever language it was read, else is
/// read now in auto; a page that fails to read is exported without text.
class ExportText {
  ExportText({
    required this.documents,
    required this.pages,
    required this.ocr,
    required this.resolve,
    required this.outputDir,
    required this.buildSearchablePdf,
  });

  final DocumentRepository documents;
  final PageRepository pages;
  final OcrRepository ocr;
  final Future<File> Function(String relativePath) resolve;
  final Future<Directory> Function() outputDir;
  final SearchablePdfBuilder buildSearchablePdf;

  /// [onProgress] counts pages read.
  Future<File> txt(String documentId, {ExportProgress? onProgress}) => _export(
    documentId,
    'txt',
    onProgress,
    (_, texts) async => utf8.encode(plainText(texts)),
  );

  Future<File> docx(String documentId, {ExportProgress? onProgress}) => _export(
    documentId,
    'docx',
    onProgress,
    (_, texts) async => buildDocx(texts),
  );

  Future<File> searchablePdf(String documentId, {ExportProgress? onProgress}) =>
      _export(
        documentId,
        'pdf',
        onProgress,
        (docPages, texts) async => buildSearchablePdf([
          // The same image the text was read from, so the boxes line up.
          for (final page in docPages)
            (await resolve(page.renderPath ?? page.originalPath)).path,
        ], texts),
      );

  Future<File> _export(
    String documentId,
    String extension,
    ExportProgress? onProgress,
    Future<Uint8List> Function(List<DocumentPage>, List<OcrResult?>) encode,
  ) async {
    final document = await documents.get(documentId);
    if (document == null) throw StateError('No document $documentId');
    final docPages = await pages.getByDocument(documentId);
    if (docPages.isEmpty) throw StateError('Document $documentId has no pages');

    final texts = <OcrResult?>[];
    for (final page in docPages) {
      try {
        texts.add(await ocr.extractText(page.id, null));
      } on OcrFailed {
        texts.add(null);
      }
      onProgress?.call(texts.length, docPages.length);
    }
    final bytes = await encode(docPages, texts);

    final dir = Directory(p.join((await outputDir()).path, documentId));
    await dir.create(recursive: true);
    final file = File(
      p.join(dir.path, '${pdfFileName(document.title)}.$extension'),
    );
    return file.writeAsBytes(bytes, flush: true);
  }
}
