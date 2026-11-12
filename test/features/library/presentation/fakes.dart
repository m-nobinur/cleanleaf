import 'dart:async';

import 'package:cleanleaf/core/storage/settings_store.dart';
import 'package:cleanleaf/features/library/domain/document.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/library/domain/document_repository.dart';
import 'package:cleanleaf/features/library/domain/page_repository.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_language.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_repository.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_result.dart';

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
  Future<List<DocumentPage>> getByDocument(String documentId) async =>
      pagesByDocument[documentId] ?? const [];

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

class MemorySettingsStore implements SettingsStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

/// Page text is `Text of <pageId>`; search matches titles and
/// [textByDocument], case-insensitively, like the LIKE search.
class FakeOcrRepository implements OcrRepository {
  FakeOcrRepository({
    this.documents,
    this.textByDocument = const {},
    this.reading = const {},
  });

  final FakeDocumentRepository? documents;
  final Map<String, String> textByDocument;
  final Set<String> reading;

  @override
  Future<OcrResult> extractText(String pageId, OcrLanguage? language) async =>
      OcrResult(
        'Text of $pageId',
        lines: const [],
        engine: 'fake',
        language: language ?? OcrLanguage.auto,
      );

  @override
  Stream<OcrStatus?> watchStatus(String pageId) => const Stream.empty();

  @override
  Stream<Set<String>> watchReadingDocumentIds() => Stream.value(reading);

  @override
  Stream<List<Document>> watchSearch(String query) async* {
    final q = query.toLowerCase();
    yield [
      for (final d in await documents!.watchAll().first)
        if ('${d.title} ${textByDocument[d.id] ?? ''}'.toLowerCase().contains(
          q,
        ))
          d,
    ];
  }
}
