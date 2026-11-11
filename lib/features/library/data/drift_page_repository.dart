import 'package:drift/drift.dart';

import '../../../core/geometry/quad.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/file_store.dart';
import '../../../core/storage/ids.dart';
import '../domain/document_page.dart';
import '../domain/page_repository.dart';
import 'page_mapper.dart';

class DriftPageRepository implements PageRepository {
  DriftPageRepository(this._db, this._files, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final FileStore _files;
  final DateTime Function() _now;

  SimpleSelectStatement<$PagesTable, PageRow> _byDocument(String documentId) =>
      _db.select(_db.pages)
        ..where((t) => t.documentId.equals(documentId))
        ..orderBy([(t) => OrderingTerm.asc(t.pageIndex)]);

  @override
  Stream<List<DocumentPage>> watchByDocument(String documentId) =>
      _byDocument(documentId)
          .watch()
          .map((rows) => rows.map(pageFromRow).toList());

  @override
  Future<List<DocumentPage>> getByDocument(String documentId) async =>
      (await _byDocument(documentId).get()).map(pageFromRow).toList();

  @override
  Future<DocumentPage?> get(String pageId) async {
    final row = await (_db.select(
      _db.pages,
    )..where((t) => t.id.equals(pageId))).getSingleOrNull();
    return row == null ? null : pageFromRow(row);
  }

  @override
  Future<DocumentPage> add(
    String documentId, {
    required Stream<List<int>> original,
    required Quad? detectedCorners,
    PageSource source = PageSource.camera,
  }) async {
    final corners = detectedCorners ?? fullFrame;
    final id = newId();
    final originalPath = await _files.writePageFile(
      documentId,
      id,
      PageFile.original,
      original,
    );
    try {
      return await _db.transaction(() async {
        final count = await _countPages(documentId);
        // Google's scans are final when added; ours are read once rendered.
        final ocrStatus = source == PageSource.googleScanner
            ? OcrStatus.pending
            : null;
        final page = DocumentPage(
          id,
          documentId: documentId,
          index: count,
          originalPath: originalPath,
          corners: corners,
          detectedCorners: detectedCorners,
          source: source,
          ocrStatus: ocrStatus,
        );
        await _db
            .into(_db.pages)
            .insert(
              PagesCompanion.insert(
                id: id,
                documentId: documentId,
                pageIndex: page.index,
                originalPath: originalPath,
                corners: encodeCorners(corners),
                source: source.name,
                detectedCorners: Value.absentIfNull(
                  detectedCorners == null
                      ? null
                      : encodeCorners(detectedCorners),
                ),
                anchors: encodeAnchors(page.anchors),
                rotation: page.rotation,
                filter: page.filter.name,
                filterParams: encodeFilterParams(page.filterParams),
                ocrStatus: Value.absentIfNull(ocrStatus?.name),
              ),
            );
        await _touch(documentId);
        return page;
      });
    } catch (_) {
      await _files.deletePage(documentId, id);
      rethrow;
    }
  }

  @override
  Future<void> updateEdits(DocumentPage page) => _db.transaction(() async {
    await (_db.update(_db.pages)..where((t) => t.id.equals(page.id))).write(
      PagesCompanion(
        corners: Value(encodeCorners(page.corners)),
        anchors: Value(encodeAnchors(page.anchors)),
        rotation: Value(page.rotation),
        filter: Value(page.filter.name),
        filterParams: Value(encodeFilterParams(page.filterParams)),
      ),
    );
    await _touch(page.documentId);
  });

  @override
  Future<void> saveRender(
    String pageId, {
    required Stream<List<int>> render,
    required Stream<List<int>> thumb,
  }) async {
    final row = await _row(pageId);
    final renderPath = await _files.writePageFile(
      row.documentId,
      pageId,
      PageFile.render,
      render,
    );
    final thumbPath = await _files.writePageFile(
      row.documentId,
      pageId,
      PageFile.thumb,
      thumb,
    );
    await (_db.update(_db.pages)..where((t) => t.id.equals(pageId))).write(
      PagesCompanion(
        renderPath: Value(renderPath),
        thumbPath: Value(thumbPath),
        // A new render invalidates the text and its word boxes.
        ocrStatus: Value(OcrStatus.pending.name),
        ocrText: const Value(null),
        ocrWords: const Value(null),
      ),
    );
  }

  @override
  Future<void> delete(String pageId) async {
    final row = await _row(pageId);
    await _db.transaction(() async {
      await (_db.delete(_db.pages)..where((t) => t.id.equals(pageId))).go();
      final remaining = await _byDocument(row.documentId).get();
      await _writeOrder(remaining.map((r) => r.id).toList());
      await _touch(row.documentId);
    });
    await _files.deletePage(row.documentId, pageId);
  }

  @override
  Future<void> reorder(String documentId, List<String> pageIds) =>
      _db.transaction(() async {
        final current = await _byDocument(documentId).get();
        final ids = pageIds.toSet();
        if (ids.length != pageIds.length ||
            ids.length != current.length ||
            !current.every((r) => ids.contains(r.id))) {
          throw ArgumentError.value(
            pageIds,
            'pageIds',
            'must list every page of $documentId exactly once',
          );
        }
        await _writeOrder(pageIds);
        await _touch(documentId);
      });

  Future<void> _writeOrder(List<String> pageIds) async {
    for (final (index, id) in pageIds.indexed) {
      await (_db.update(_db.pages)..where((t) => t.id.equals(id))).write(
        PagesCompanion(pageIndex: Value(index)),
      );
    }
  }

  Future<PageRow> _row(String pageId) =>
      (_db.select(_db.pages)..where((t) => t.id.equals(pageId))).getSingle();

  Future<int> _countPages(String documentId) {
    final count = _db.pages.id.count();
    return (_db.selectOnly(_db.pages)
          ..addColumns([count])
          ..where(_db.pages.documentId.equals(documentId)))
        .map((r) => r.read(count)!)
        .getSingle();
  }

  Future<void> _touch(String documentId) =>
      (_db.update(_db.documents)..where((t) => t.id.equals(documentId))).write(
        DocumentsCompanion(updatedAt: Value(_now().millisecondsSinceEpoch)),
      );
}
