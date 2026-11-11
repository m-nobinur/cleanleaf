import 'dart:io';
import 'dart:typed_data';

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/features/enhance/domain/page_renderer.dart';
import 'package:cleanleaf/features/export/domain/export_png.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../library/presentation/fakes.dart';

class _Pages extends FakePageRepository {
  _Pages(super.pagesByDocument);

  @override
  Future<List<DocumentPage>> getByDocument(String documentId) async =>
      pagesByDocument[documentId] ?? const [];
}

class _Renderer extends Fake implements PageRenderer {
  final calls = <String>[];

  @override
  Future<Uint8List> render(
    String originalPath,
    Quad quad,
    int rotation,
    PageFilter filter,
    Map<String, double> params, {
    int maxLongSide = 0,
    bool png = false,
  }) async {
    calls.add(
      '${p.basename(p.dirname(originalPath))} $rotation ${filter.name} '
      '$params $maxLongSide $png',
    );
    return Uint8List.fromList([rotation]);
  }
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('export_png'));
  tearDown(() => root.deleteSync(recursive: true));

  test('renders every page from its original with its saved edits', () async {
    final renderer = _Renderer();
    final export = ExportPng(
      documents: FakeDocumentRepository([fakeDocument('d', 'Notes')]),
      pages: _Pages({
        'd': [
          DocumentPage(
            'p1',
            documentId: 'd',
            index: 0,
            originalPath: 'docs/d/p1/original.jpg',
            renderPath: 'docs/d/p1/render.jpg',
            corners: fullFrame,
            rotation: 90,
            filter: PageFilter.grayscale,
            filterParams: const {'brightness': 0.2},
          ),
          DocumentPage(
            'p2',
            documentId: 'd',
            index: 1,
            originalPath: 'docs/d/p2/original.jpg',
            corners: fullFrame,
          ),
        ],
      }),
      resolve: (rel) async => File(p.join(root.path, rel)),
      outputDir: () async => Directory(p.join(root.path, 'out')),
      renderer: renderer,
    );

    final files = await export('d');

    expect(renderer.calls, [
      'p1 90 grayscale {brightness: 0.2} 0 true',
      'p2 0 enhancedColor {} 0 true',
    ]);
    expect(files.map((f) => p.basename(f.path)), [
      'Notes-01.png',
      'Notes-02.png',
    ]);
    expect(files.first.readAsBytesSync(), [90]);
  });
}
