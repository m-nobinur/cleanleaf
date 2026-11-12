import '../../library/domain/document.dart';
import '../../library/domain/document_page.dart';
import 'ocr_language.dart';
import 'ocr_result.dart';

class OcrFailed implements Exception {
  const OcrFailed(this.pageId);

  final String pageId;

  @override
  String toString() => 'OcrFailed($pageId)';
}

abstract interface class OcrRepository {
  /// Null until the page is queued.
  Stream<OcrStatus?> watchStatus(String pageId);

  /// Documents with a page waiting for or undergoing OCR.
  Stream<Set<String>> watchReadingDocumentIds();

  /// The stored result when the page was read in [language] (any language
  /// when null); otherwise queues the page ahead of background work, in
  /// [language] or auto, and completes when it is read. Throws [OcrFailed].
  Future<OcrResult> extractText(String pageId, OcrLanguage? language);

  /// Documents whose title or page text contains every whitespace-separated
  /// term of [query], most recently updated first; all documents when blank.
  Stream<List<Document>> watchSearch(String query);
}
