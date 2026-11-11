import 'dart:io';

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/features/capture/data/camera_scan.dart';
import 'package:cleanleaf/features/capture/domain/scan_mode.dart';
import 'package:cleanleaf/features/enhance/domain/page_renderer.dart';
import 'package:cleanleaf/features/library/domain/document.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/library/domain/document_repository.dart';
import 'package:cleanleaf/features/library/domain/page_repository.dart';
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
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
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
  Quad? detected;
  PageSource? source;
  List<int> stored = [];
  DocumentPage? edited;

  @override
  Future<DocumentPage> add(
    String documentId, {
    required Stream<List<int>> original,
    required Quad? detectedCorners,
    PageSource source = PageSource.camera,
  }) async {
    if (fail) throw StateError('disk full');
    detected = detectedCorners;
    this.source = source;
    await for (final chunk in original) {
      stored.addAll(chunk);
    }
    return DocumentPage(
      'p1',
      documentId: documentId,
      index: 0,
      originalPath: 'x',
      corners: detectedCorners ?? fullFrame,
      detectedCorners: detectedCorners,
    );
  }

  @override
  Future<void> updateEdits(DocumentPage page) async => edited = page;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const Quad stillQuad = (
  topLeft: (x: 0.1, y: 0.1),
  topRight: (x: 0.9, y: 0.1),
  bottomRight: (x: 0.9, y: 0.9),
  bottomLeft: (x: 0.1, y: 0.9),
);

const Quad liveQuad = (
  topLeft: (x: 0.2, y: 0.2),
  topRight: (x: 0.8, y: 0.2),
  bottomRight: (x: 0.8, y: 0.8),
  bottomLeft: (x: 0.2, y: 0.8),
);

void main() {
  late Directory temp;
  late File still;
  late _Documents documents;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('cleanleaf_capture_');
    still = File('${temp.path}/still.jpg')..writeAsBytesSync([1, 2, 3]);
    documents = _Documents();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  CameraScan scan(_Pages pages, {Quad? detected, bool detectThrows = false}) =>
      CameraScan(
        detect: (_) async {
          if (detectThrows) throw StateError('ffi');
          return detected;
        },
        documents: documents,
        pages: pages,
        now: () => DateTime(2026, 11, 12, 9, 5),
      );

  test(
    'stores the still with its re-detected corners as a camera page',
    () async {
      final pages = _Pages();
      final page = await scan(pages, detected: stillQuad)(
        still.path,
        mode: ScanMode.document,
        liveQuad: liveQuad,
      );
      expect(documents.created, ['Scan 2026-11-12 09.05']);
      expect(pages.detected, stillQuad);
      expect(pages.source, PageSource.camera);
      expect(pages.stored, [1, 2, 3]);
      expect(page.filter, PageFilter.enhancedColor);
      expect(still.existsSync(), isFalse);
    },
  );

  test('falls back to the live corners when the still has none', () async {
    final pages = _Pages();
    await scan(pages)(still.path, mode: ScanMode.document, liveQuad: liveQuad);
    expect(pages.detected, liveQuad);
  });

  test('a failing re-detection still saves the shot', () async {
    final pages = _Pages();
    await scan(pages, detectThrows: true)(still.path, mode: ScanMode.document);
    expect(pages.detected, isNull);
    expect(pages.stored, [1, 2, 3]);
  });

  test('applies the mode presets', () async {
    final pages = _Pages();
    final card = await scan(pages)(still.path, mode: ScanMode.idCard);
    expect(card.filter, PageFilter.original);
    expect(card.filterParams, {aspectRatioParam: PageAspect.id1.ratio});
    expect(pages.edited, same(card));

    still.writeAsBytesSync([1]);
    final receipt = await scan(_Pages())(still.path, mode: ScanMode.receipt);
    expect(receipt.filter, PageFilter.grayscale);
    expect(receipt.filterParams, isEmpty);
  });

  test(
    'rolls back the document and drops the still when saving fails',
    () async {
      await expectLater(
        scan(_Pages(fail: true))(still.path, mode: ScanMode.document),
        throwsStateError,
      );
      expect(documents.deleted, ['d1']);
      expect(still.existsSync(), isFalse);
    },
  );
}
