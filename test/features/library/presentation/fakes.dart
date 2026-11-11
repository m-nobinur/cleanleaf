import 'dart:async';

import 'package:cleanleaf/features/library/domain/document.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/library/domain/document_repository.dart';
import 'package:cleanleaf/features/library/domain/page_repository.dart';

Document fakeDocument(String id, String title, {int minute = 0}) => Document(
  id,
  title: title,
  createdAt: DateTime(2026, 11, 11, 9, minute),
  updatedAt: DateTime(2026, 11, 11, 9, minute),
);

class FakeDocumentRepository implements DocumentRepository {
  FakeDocumentRepository([List<Document> initial = const []])
    : _documents = [...initial];

  final List<Document> _documents;
  final _changes = StreamController<void>.broadcast();
  final deleted = <String>[];

  List<Document> get _sorted =>
      [..._documents]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Stream<List<Document>> watchAll() async* {
    yield _sorted;
    await for (final _ in _changes.stream) {
      yield _sorted;
    }
  }

  @override
  Future<Document?> get(String id) async =>
      _documents.where((d) => d.id == id).firstOrNull;

  @override
  Future<Document> create(String title) => throw UnimplementedError();

  @override
  Future<void> rename(String id, String title) async {
    final i = _documents.indexWhere((d) => d.id == id);
    final old = _documents[i];
    _documents[i] = Document(
      id,
      title: title,
      createdAt: old.createdAt,
      updatedAt: DateTime(2026, 11, 12),
    );
    _changes.add(null);
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    _documents.removeWhere((d) => d.id == id);
    _changes.add(null);
  }
}

class FakePageRepository implements PageRepository {
  FakePageRepository([this.pagesByDocument = const {}]);

  final Map<String, List<DocumentPage>> pagesByDocument;

  @override
  Stream<List<DocumentPage>> watchByDocument(String documentId) =>
      Stream.value(pagesByDocument[documentId] ?? const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

DocumentPage fakePage(String id, String documentId, int index) => DocumentPage(
  id,
  documentId: documentId,
  index: index,
  originalPath: 'docs/$documentId/$id/original.jpg',
  corners: fullFrame,
);
