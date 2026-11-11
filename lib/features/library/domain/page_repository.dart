import '../../../core/geometry/quad.dart';
import 'document_page.dart';

abstract interface class PageRepository {
  /// Ordered by index.
  Stream<List<DocumentPage>> watchByDocument(String documentId);

  Future<List<DocumentPage>> getByDocument(String documentId);

  Future<DocumentPage?> get(String pageId);

  /// Stores [original] and appends the page at the end of the document.
  /// Corners start at [detectedCorners], or the full frame when none.
  Future<DocumentPage> add(
    String documentId, {
    required Stream<List<int>> original,
    required Quad? detectedCorners,
  });

  /// Saves the edit parameters (corners, anchors, rotation, filter, params).
  Future<void> updateEdits(DocumentPage page);

  Future<void> saveRender(
    String pageId, {
    required Stream<List<int>> render,
    required Stream<List<int>> thumb,
  });

  Future<void> delete(String pageId);

  /// [pageIds] must be exactly the document's pages, in the new order.
  Future<void> reorder(String documentId, List<String> pageIds);
}
