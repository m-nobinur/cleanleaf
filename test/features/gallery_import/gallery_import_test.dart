import 'dart:io';
import 'dart:ui' as ui;

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/features/enhance/data/native_page_renderer.dart';
import 'package:cleanleaf/features/gallery_import/data/gallery_import.dart';
import 'package:cleanleaf/features/library/domain/document.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/library/domain/document_repository.dart';
import 'package:cleanleaf/features/library/domain/page_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _Documents implements DocumentRepository {
  final deleted = <String>[];

  @override
  Future<Document> create(String title) async => Document(
    'd1',
    title: title,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  Future<void> delete(String id) async => deleted.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Pages implements PageRepository {
  _Pages({this.fail = false});

  final bool fail;
  Quad? corners;
  PageSource? source;
  List<int> stored = [];

  @override
  Future<DocumentPage> add(
    String documentId, {
    required Stream<List<int>> original,
    required Quad? detectedCorners,
    PageSource source = PageSource.camera,
  }) async {
    if (fail) throw StateError('disk full');
    corners = detectedCorners;
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
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late Directory temp;
  late File photo;
  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('cleanleaf_import_');
    photo = File('${temp.path}/photo.jpg')..writeAsBytesSync([1, 2, 3]);
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  const detected = (
    topLeft: (x: 0.1, y: 0.1),
    topRight: (x: 0.9, y: 0.1),
    bottomRight: (x: 0.9, y: 0.9),
    bottomLeft: (x: 0.1, y: 0.9),
  );

  GalleryImport build(
    _Documents docs,
    _Pages pages, {
    String? picked,
    Quad? quad,
  }) => GalleryImport(
    pick: () async => picked,
    detect: (_) async => quad,
    documents: docs,
    pages: pages,
  );

  test('stores the original with detected corners as a gallery page', () async {
    final pages = _Pages();
    final page = await build(
      _Documents(),
      pages,
      picked: photo.path,
      quad: detected,
    )();
    expect(page?.documentId, 'd1');
    expect(pages.corners, detected);
    expect(pages.source, PageSource.gallery);
    expect(pages.stored, [1, 2, 3]);
  });

  test('cancelled pick creates nothing', () async {
    final pages = _Pages();
    expect(await build(_Documents(), pages)(), isNull);
    expect(pages.source, isNull);
  });

  test('a failed save removes the new document', () async {
    final docs = _Documents();
    final import = build(docs, _Pages(fail: true), picked: photo.path);
    await expectLater(import(), throwsStateError);
    expect(docs.deleted, ['d1']);
  });

  test('EXIF-rotated original: editor decode and render are upright', () async {
    final source = img.Image(width: 120, height: 90)
      ..exif.imageIfd.orientation = 6;
    img.fill(source, color: img.ColorRgb8(200, 200, 200));
    final rotated = File('${temp.path}/exif6.jpg')
      ..writeAsBytesSync(img.encodeJpg(source));

    final codec = await ui.instantiateImageCodec(rotated.readAsBytesSync());
    final frame = (await codec.getNextFrame()).image;
    final out = img.decodeJpg(
      await const NativePageRenderer().render(
        rotated.path,
        fullFrame,
        0,
        PageFilter.original,
        const {},
      ),
    )!;

    expect((frame.width, frame.height), (90, 120));
    expect((out.width, out.height), (90, 120));
  });
}
