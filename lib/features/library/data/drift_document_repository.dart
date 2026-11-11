import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/file_store.dart';
import '../../../core/storage/ids.dart';
import '../domain/document.dart';
import '../domain/document_repository.dart';

class DriftDocumentRepository implements DocumentRepository {
  DriftDocumentRepository(this._db, this._files, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final FileStore _files;
  final DateTime Function() _now;

  @override
  Stream<List<Document>> watchAll() =>
      (_db.select(_db.documents)
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .watch()
          .map((rows) => rows.map(documentFromRow).toList());

  @override
  Future<Document?> get(String id) async {
    final row = await (_db.select(
      _db.documents,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : documentFromRow(row);
  }

  @override
  Future<Document> create(String title) async {
    final now = _now().millisecondsSinceEpoch;
    final row = DocumentRow(
      id: newId(),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.documents).insert(row);
    return documentFromRow(row);
  }

  @override
  Future<void> rename(String id, String title) =>
      (_db.update(_db.documents)..where((t) => t.id.equals(id))).write(
        DocumentsCompanion(
          title: Value(title),
          updatedAt: Value(_now().millisecondsSinceEpoch),
        ),
      );

  @override
  Future<void> delete(String id) async {
    // Row first: an orphan folder is harmless, a row without files is not.
    await (_db.delete(_db.documents)..where((t) => t.id.equals(id))).go();
    await _files.deleteDocument(id);
  }
}

Document documentFromRow(DocumentRow r) => Document(
  r.id,
  title: r.title,
  createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt),
  folderId: r.folderId,
);
