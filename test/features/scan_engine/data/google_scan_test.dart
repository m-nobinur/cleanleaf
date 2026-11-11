import 'dart:io';

import 'package:cleanleaf/features/library/domain/document.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/library/domain/document_repository.dart';
import 'package:cleanleaf/features/library/domain/page_repository.dart';
import 'package:cleanleaf/features/scan_engine/data/google_scan.dart';
import 'package:flutter_test/flutter_test.dart';

class _Documents implements DocumentRepository {
  final created = <String>[];
  final deleted = <String>[];

  @override
  Future<Document> create(String title) async {
    created.add(title);
    return Document(
      'd1',
      title: title,
      createdAt: DateTime(0),
      updatedAt: DateTime(0),
    );
  }

  @override
  Future<void> delete(String id) async => deleted.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Pages implements PageRepository {
  _Pages({this.fail = false});

  final bool fail;
  List<int>? stored;
  PageSource? source;
  DocumentPage? edited;

  @override
  Future<DocumentPage> add(
    String documentId, {
    required Stream<List<int>> original,
    required detectedCorners,
    PageSource source = PageSource.camera,
  }) async {
    if (fail) throw StateError('disk full');
    stored = [await for (final chunk in original) ...chunk];
    this.source = source;
    return DocumentPage(
      'p1',
      documentId: documentId,
      index: 0,
      originalPath: 'docs/$documentId/p1/original.jpg',
      corners: fullFrame,
      source: source,
    );
  }

  @override
  Future<void> updateEdits(DocumentPage page) async => edited = page;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late Directory dir;
  late File jpeg;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('google_scan');
    jpeg = File('${dir.path}/scan.jpg')..writeAsBytesSync([1, 2, 3]);
  });
  tearDown(() => dir.delete(recursive: true));

  GoogleScan scanWith(String? path, _Documents docs, _Pages pages) =>
      GoogleScan(
        scan: () async => path,
        documents: docs,
        pages: pages,
        now: () => DateTime(2026, 11, 11, 9, 5),
      );

  test(
    'stores the result as an unfiltered Google page and drops the temp',
    () async {
      final docs = _Documents();
      final pages = _Pages();
      final page = await scanWith(jpeg.path, docs, pages)();

      expect(docs.created, ['Scan 2026-11-11 09.05']);
      expect(pages.stored, [1, 2, 3]);
      expect(pages.source, PageSource.googleScanner);
      expect(pages.edited?.filter, PageFilter.original);
      expect(pages.edited?.detectedCorners, isNull);
      expect(page?.filter, PageFilter.original);
      expect(jpeg.existsSync(), isFalse);
    },
  );

  test('a cancelled scan creates nothing', () async {
    final docs = _Documents();
    expect(await scanWith(null, docs, _Pages())(), isNull);
    expect(docs.created, isEmpty);
  });

  test('a failed save removes the empty document', () async {
    final docs = _Documents();
    await expectLater(
      scanWith(jpeg.path, docs, _Pages(fail: true))(),
      throwsStateError,
    );
    expect(docs.deleted, ['d1']);
  });
}
