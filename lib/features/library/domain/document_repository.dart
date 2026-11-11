import 'document.dart';

abstract interface class DocumentRepository {
  /// Most recently updated first.
  Stream<List<Document>> watchAll();

  Future<Document?> get(String id);

  Future<Document> create(String title);

  Future<void> rename(String id, String title);

  /// Also deletes the document's pages and files.
  Future<void> delete(String id);
}
