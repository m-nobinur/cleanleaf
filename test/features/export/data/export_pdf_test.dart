import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleanleaf/features/export/data/pdf_isolate_builder.dart';
import 'package:cleanleaf/features/export/domain/export_pdf.dart';
import 'package:cleanleaf/features/library/domain/document.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/library/domain/document_repository.dart';
import 'package:cleanleaf/features/library/domain/page_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

class _MockDocuments extends Mock implements DocumentRepository {}

class _MockPages extends Mock implements PageRepository {}

DocumentPage _page(int index, String original, {String? render}) =>
    DocumentPage(
      'p$index',
      documentId: 'd1',
      index: index,
      originalPath: original,
      corners: fullFrame,
      renderPath: render,
    );

void _writeJpeg(Directory root, String relative, int w, int h) {
  final file = File(p.join(root.path, relative))
    ..parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodeJpg(img.Image(width: w, height: h)));
}

List<List<double>> _mediaBoxes(Uint8List pdf) =>
    RegExp(r'/MediaBox\s*\[([^\]]+)\]')
        .allMatches(latin1.decode(pdf))
        .map(
          (m) => m[1]!.trim().split(RegExp(r'\s+')).map(double.parse).toList(),
        )
        .toList();

int _pageCount(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page(?![a-zA-Z])').allMatches(latin1.decode(pdf)).length;

void main() {
  late Directory root;
  late _MockDocuments documents;
  late _MockPages pages;
  late ExportPdf export;
  final progress = <(int, int)>[];

  setUp(() {
    root = Directory.systemTemp.createTempSync('export_pdf_test');
    documents = _MockDocuments();
    pages = _MockPages();
    progress.clear();
    export = ExportPdf(
      documents: documents,
      pages: pages,
      resolve: (relative) async => File(p.join(root.path, relative)),
      outputDir: () async => Directory(p.join(root.path, 'cache')),
      build: buildPdfInIsolate,
    );
    when(() => documents.get('d1')).thenAnswer(
      (_) async => Document(
        'd1',
        title: 'Rent: 11/11',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('writes one A4-fitted page per image, render before original', () async {
    _writeJpeg(root, 'a/original.jpg', 600, 800);
    _writeJpeg(root, 'a/render.jpg', 300, 400);
    _writeJpeg(root, 'b/original.jpg', 400, 300);
    when(() => pages.getByDocument('d1')).thenAnswer(
      (_) async => [
        _page(0, 'a/original.jpg', render: 'a/render.jpg'),
        _page(1, 'b/original.jpg'),
      ],
    );

    final file = await export('d1', onProgress: (d, t) => progress.add((d, t)));

    expect(p.basename(file.path), 'Rent_ 11_11.pdf');
    final bytes = file.readAsBytesSync();
    expect(_pageCount(bytes), 2);
    final boxes = _mediaBoxes(bytes);
    expect(boxes, hasLength(2));
    // 300x400 and 400x300 both fit A4 (595.28 x 841.89) by width.
    expect(boxes[0][2], closeTo(595.28, 0.01));
    expect(boxes[0][3], closeTo(793.70, 0.01));
    expect(boxes[1][2], closeTo(595.28, 0.01));
    expect(boxes[1][3], closeTo(446.46, 0.01));
    expect(progress.last, (2, 2));
  });

  test('rejects a document with no pages', () {
    when(() => pages.getByDocument('d1')).thenAnswer((_) async => []);
    expect(() => export('d1'), throwsStateError);
  });
}
