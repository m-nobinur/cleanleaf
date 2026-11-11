import '../../../core/geometry/quad.dart';
import 'page.dart';

abstract interface class PageRepository {
  /// Ordered by index.
  Stream<List<Page>> watchByDocument(String documentId);

  Future<List<Page>> getByDocument(String documentId);

  /// Stores [original] and appends the page at the end of the document.
  Future<Page> add(
    String documentId, {
    required Stream<List<int>> original,
    required Quad corners,
  });

  /// Saves the edit parameters (corners, anchors, rotation, filter, params).
  Future<void> updateEdits(Page page);

  Future<void> saveRender(
    String pageId, {
    required Stream<List<int>> render,
    required Stream<List<int>> thumb,
  });

  Future<void> delete(String pageId);

  /// [pageIds] must be exactly the document's pages, in the new order.
  Future<void> reorder(String documentId, List<String> pageIds);
}
