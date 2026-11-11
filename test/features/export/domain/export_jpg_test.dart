import 'dart:io';

import 'package:cleanleaf/features/export/domain/export_jpg.dart';
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

DocumentPage _page(String id, int index, {bool rendered = false}) =>
    DocumentPage(
      id,
      documentId: 'd',
      index: index,
      originalPath: 'docs/d/$id/original.jpg',
      renderPath: rendered ? 'docs/d/$id/render.jpg' : null,
      corners: fullFrame,
    );

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('export_jpg'));
  tearDown(() => root.deleteSync(recursive: true));

  ExportJpg exporter(List<DocumentPage> pages, {String title = 'Tax: 2026'}) {
    for (final page in pages) {
      for (final rel in [page.originalPath, ?page.renderPath]) {
        File(p.join(root.path, rel))
          ..createSync(recursive: true)
          ..writeAsStringSync(rel);
      }
    }
    return ExportJpg(
      documents: FakeDocumentRepository([fakeDocument('d', title)]),
      pages: _Pages({'d': pages}),
      resolve: (rel) async => File(p.join(root.path, rel)),
      outputDir: () async => Directory(p.join(root.path, 'out')),
    );
  }

  test('names pages in order and prefers the render', () async {
    final files = await exporter([
      _page('p1', 0, rendered: true),
      _page('p2', 1),
    ])('d');
    expect(files.map((f) => p.basename(f.path)), [
      'Tax_ 2026-01.jpg',
      'Tax_ 2026-02.jpg',
    ]);
    expect(files.map((f) => f.readAsStringSync()), [
      'docs/d/p1/render.jpg',
      'docs/d/p2/original.jpg',
    ]);
  });

  test('a single page keeps the plain title', () async {
    final files = await exporter([_page('p1', 0)], title: 'Receipt')('d');
    expect(p.basename(files.single.path), 'Receipt.jpg');
  });

  test('a re-export drops files from a longer earlier export', () async {
    await exporter([_page('p1', 0), _page('p2', 1)])('d');
    final files = await exporter([_page('p1', 0)], title: 'Tax: 2026')('d');
    expect(files.single.parent.listSync(), hasLength(1));
  });
}
