import 'dart:async';

import '../../../core/geometry/quad.dart';
import '../../../core/metrics/ab_session.dart';
import '../../../core/storage/file_store.dart';
import '../domain/document_page.dart';
import '../domain/page_repository.dart';

/// Copies every stored original and render into the [AbSession], without
/// delaying or failing the save.
class AbRecordingPageRepository implements PageRepository {
  AbRecordingPageRepository(this._inner, this._files, this._session);

  final PageRepository _inner;
  final FileStore _files;
  final AbSession _session;

  @override
  Future<DocumentPage> add(
    String documentId, {
    required Stream<List<int>> original,
    required Quad? detectedCorners,
    PageSource source = PageSource.camera,
  }) async {
    final page = await _inner.add(
      documentId,
      original: original,
      detectedCorners: detectedCorners,
      source: source,
    );
    unawaited(
      _record(page.id, 'original', () async => page.originalPath, {
        'doc': documentId,
        'source': source.name,
      }),
    );
    return page;
  }

  @override
  Future<void> saveRender(
    String pageId, {
    required Stream<List<int>> render,
    required Stream<List<int>> thumb,
  }) async {
    await _inner.saveRender(pageId, render: render, thumb: thumb);
    unawaited(
      _record(
        pageId,
        'render',
        () async => (await _inner.get(pageId))?.renderPath,
        const {},
      ),
    );
  }

  Future<void> _record(
    String pageId,
    String kind,
    Future<String?> Function() relativePath,
    Map<String, Object?> fields,
  ) => _session.copy(kind, '$pageId.$kind.jpg', () async {
    final path = await relativePath();
    return path == null ? null : _files.resolve(path);
  }, {'page': pageId, ...fields});

  @override
  Stream<List<DocumentPage>> watchByDocument(String documentId) =>
      _inner.watchByDocument(documentId);

  @override
  Future<List<DocumentPage>> getByDocument(String documentId) =>
      _inner.getByDocument(documentId);

  @override
  Future<DocumentPage?> get(String pageId) => _inner.get(pageId);

  @override
  Future<void> updateEdits(DocumentPage page) => _inner.updateEdits(page);

  @override
  Future<void> delete(String pageId) => _inner.delete(pageId);

  @override
  Future<void> reorder(String documentId, List<String> pageIds) =>
      _inner.reorder(documentId, pageIds);
}
