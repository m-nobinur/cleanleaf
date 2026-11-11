import 'dart:io';

import 'package:cleanleaf/core/storage/app_database.dart';
import 'package:cleanleaf/core/storage/file_store.dart';
import 'package:cleanleaf/features/library/data/drift_document_repository.dart';
import 'package:cleanleaf/features/library/data/drift_page_repository.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late AppDatabase db;
  late DriftDocumentRepository docs;
  late DriftPageRepository pages;
  var tick = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('repo_test');
    db = AppDatabase(NativeDatabase.memory());
    final files = FileStore(() async => root);
    DateTime clock() => DateTime.fromMillisecondsSinceEpoch(++tick);
    docs = DriftDocumentRepository(db, files, clock: clock);
    pages = DriftPageRepository(db, files, clock: clock);
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<DocumentPage> addPage(String docId) =>
      pages.add(docId, original: Stream.value([1, 2]), detectedCorners: null);

  Future<List<String>> pageIds(String docId) async =>
      (await pages.getByDocument(docId)).map((p) => p.id).toList();

  Future<List<int>> indices(String docId) async =>
      (await pages.getByDocument(docId)).map((p) => p.index).toList();

  group('documents', () {
    test('create, get, rename', () async {
      final doc = await docs.create('Receipt');
      expect((await docs.get(doc.id))!.title, 'Receipt');

      await docs.rename(doc.id, 'Invoice');
      final renamed = (await docs.get(doc.id))!;
      expect(renamed.title, 'Invoice');
      expect(renamed.updatedAt.isAfter(doc.updatedAt), isTrue);
      expect(renamed.createdAt, doc.createdAt);
    });

    test('watchAll lists most recently updated first', () async {
      final a = await docs.create('A');
      final b = await docs.create('B');
      expect((await docs.watchAll().first).map((d) => d.id), [b.id, a.id]);

      await addPage(a.id);
      expect((await docs.watchAll().first).map((d) => d.id), [a.id, b.id]);
    });

    test('delete cascades pages and files', () async {
      final doc = await docs.create('A');
      final page = await addPage(doc.id);
      final original = await FileStore(() async => root)
          .resolve(page.originalPath);
      expect(original.existsSync(), isTrue);

      await docs.delete(doc.id);

      expect(await docs.get(doc.id), isNull);
      expect(await db.select(db.pages).get(), isEmpty);
      expect(Directory('${root.path}/docs/${doc.id}').existsSync(), isFalse);
    });
  });

  group('pages', () {
    test('add appends with contiguous indices and default edits', () async {
      final doc = await docs.create('A');
      final first = await addPage(doc.id);
      await addPage(doc.id);

      expect(await indices(doc.id), [0, 1]);
      expect(first.originalPath, 'docs/${doc.id}/${first.id}/original.jpg');
      final stored = (await pages.getByDocument(doc.id)).first;
      expect(stored.corners, fullFrame);
      expect(stored.anchors, noAnchors);
      expect(stored.filter, PageFilter.enhancedColor);
    });

    test('updateEdits round-trips every edit parameter', () async {
      final doc = await docs.create('A');
      final page = await addPage(doc.id);
      const corners = (
        topLeft: (x: 0.1, y: 0.2),
        topRight: (x: 0.9, y: 0.15),
        bottomRight: (x: 0.85, y: 0.95),
        bottomLeft: (x: 0.05, y: 0.9),
      );
      final edited = page.copyWith(
        corners: corners,
        anchors: [
          [(x: 0.5, y: 0.1)],
          [],
          [(x: 0.4, y: 0.96), (x: 0.6, y: 0.97)],
          [],
        ],
        rotation: 90,
        filter: PageFilter.blackWhite,
        filterParams: {'threshold': 0.4},
      );

      await pages.updateEdits(edited);

      final stored = (await pages.getByDocument(doc.id)).single;
      expect(stored.corners, corners);
      expect(stored.anchors, edited.anchors);
      expect(stored.rotation, 90);
      expect(stored.filter, PageFilter.blackWhite);
      expect(stored.filterParams, {'threshold': 0.4});
    });

    test('get finds a page by id; detected corners survive edits', () async {
      final doc = await docs.create('A');
      const detected = (
        topLeft: (x: 0.1, y: 0.1),
        topRight: (x: 0.9, y: 0.1),
        bottomRight: (x: 0.9, y: 0.9),
        bottomLeft: (x: 0.1, y: 0.9),
      );
      final page = await pages.add(
        doc.id,
        original: Stream.value([1]),
        detectedCorners: detected,
      );
      expect(page.corners, detected);

      await pages.updateEdits(page.copyWith(corners: fullFrame));

      final stored = (await pages.get(page.id))!;
      expect(stored.corners, fullFrame);
      expect(stored.detectedCorners, detected);
      expect((await addPage(doc.id)).detectedCorners, isNull);
      expect(await pages.get('missing'), isNull);
    });

    test('saveRender stores render and thumb paths', () async {
      final doc = await docs.create('A');
      final page = await addPage(doc.id);

      await pages.saveRender(
        page.id,
        render: Stream.value([3]),
        thumb: Stream.value([4]),
      );

      final stored = (await pages.getByDocument(doc.id)).single;
      expect(stored.renderPath, 'docs/${doc.id}/${page.id}/render.jpg');
      expect(stored.thumbPath, 'docs/${doc.id}/${page.id}/thumb.jpg');
    });

    test('reorder keeps contiguous indices in the new order', () async {
      final doc = await docs.create('A');
      final [p0, p1, p2] = [
        for (var i = 0; i < 3; i++) (await addPage(doc.id)).id,
      ];

      await pages.reorder(doc.id, [p2, p0, p1]);

      expect(await pageIds(doc.id), [p2, p0, p1]);
      expect(await indices(doc.id), [0, 1, 2]);
    });

    test('reorder rejects a list that is not exactly the pages', () async {
      final doc = await docs.create('A');
      final p0 = (await addPage(doc.id)).id;
      final p1 = (await addPage(doc.id)).id;

      await expectLater(pages.reorder(doc.id, [p0]), throwsArgumentError);
      await expectLater(pages.reorder(doc.id, [p0, p0]), throwsArgumentError);
      expect(await pageIds(doc.id), [p0, p1]);
    });

    test('delete re-compacts indices and removes the page folder', () async {
      final doc = await docs.create('A');
      final [p0, p1, p2] = [
        for (var i = 0; i < 3; i++) (await addPage(doc.id)).id,
      ];

      await pages.delete(p1);

      expect(await pageIds(doc.id), [p0, p2]);
      expect(await indices(doc.id), [0, 1]);
      expect(
        Directory('${root.path}/docs/${doc.id}/$p1').existsSync(),
        isFalse,
      );
      expect(Directory('${root.path}/docs/${doc.id}/$p0').existsSync(), isTrue);
    });

    test('foreign keys reject a page for a missing document', () async {
      await expectLater(addPage('missing'), throwsA(isA<SqliteException>()));
      expect(Directory('${root.path}/docs/missing').listSync(), isEmpty);
    });
  });
}
