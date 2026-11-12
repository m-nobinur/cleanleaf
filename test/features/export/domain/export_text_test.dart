import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cleanleaf/features/export/domain/docx.dart';
import 'package:cleanleaf/features/export/domain/export_text.dart';
import 'package:cleanleaf/features/export/domain/plain_text.dart';
import 'package:cleanleaf/features/library/domain/document.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/library/domain/document_repository.dart';
import 'package:cleanleaf/features/library/domain/page_repository.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_language.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_repository.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

class _MockDocuments extends Mock implements DocumentRepository {}

class _MockPages extends Mock implements PageRepository {}

class _MockOcr extends Mock implements OcrRepository {}

OcrResult _text(String text) => OcrResult(
  text,
  lines: const [],
  engine: 'tesseract',
  language: OcrLanguage.auto,
);

DocumentPage _page(int index, {String? render}) => DocumentPage(
  'p$index',
  documentId: 'd1',
  index: index,
  originalPath: 'p$index/original.jpg',
  corners: fullFrame,
  renderPath: render,
);

String _documentXml(Uint8List docx) => utf8.decode(
  ZipDecoder().decodeBytes(docx).findFile('word/document.xml')!.content,
);

void main() {
  group('plainText', () {
    test('joins pages and blocks with one blank line, skipping null', () {
      expect(
        plainText([
          _text('Invoice #42\nTotal 1,250\n\n\nআমার সোনার বাংলা\n'),
          null,
          _text('  \n'),
          _text('Page three'),
        ]),
        'Invoice #42\nTotal 1,250\n\nআমার সোনার বাংলা\n\nPage three',
      );
    });
  });

  group('buildDocx', () {
    test('writes a valid package with escaped paragraphs', () {
      final docx = buildDocx([
        _text('Tom & Jerry <Ltd>\n"paid"\n\nআমার\x0b সোনার'),
      ]);
      final names = ZipDecoder().decodeBytes(docx).files.map((f) => f.name);
      expect(names, [
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
      ]);
      final xml = _documentXml(docx);
      expect(
        xml,
        contains(
          '<w:p><w:r><w:t xml:space="preserve">Tom &amp; Jerry &lt;Ltd&gt;</w:t>'
          '<w:br/><w:t xml:space="preserve">"paid"</w:t></w:r></w:p>',
        ),
      );
      expect(xml, contains('>আমার সোনার</w:t>'), reason: 'control char gone');
      expect('<w:p>'.allMatches(xml), hasLength(2));
    });

    test('breaks the page between pages only', () {
      final xml = _documentXml(buildDocx([_text('One'), null, _text('Three')]));
      expect('w:type="page"'.allMatches(xml), hasLength(2));
      expect(xml.indexOf('One'), lessThan(xml.indexOf('w:type="page"')));
      expect(xml.lastIndexOf('w:type="page"'), lessThan(xml.indexOf('Three')));
    });
  });

  group('ExportText', () {
    late Directory root;
    late _MockDocuments documents;
    late _MockPages pages;
    late _MockOcr ocr;
    late ExportText export;
    List<String>? builtImages;
    List<OcrResult?>? builtTexts;

    setUp(() {
      root = Directory.systemTemp.createTempSync('export_text_test');
      documents = _MockDocuments();
      pages = _MockPages();
      ocr = _MockOcr();
      export = ExportText(
        documents: documents,
        pages: pages,
        ocr: ocr,
        resolve: (relative) async => File(p.join(root.path, relative)),
        outputDir: () async => Directory(p.join(root.path, 'cache')),
        buildSearchablePdf: (images, texts) async {
          builtImages = images;
          builtTexts = texts;
          return Uint8List.fromList([1, 2, 3]);
        },
      );
      when(() => documents.get('d1')).thenAnswer(
        (_) async => Document(
          'd1',
          title: 'Rent: 11/11',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      when(
        () => pages.getByDocument('d1'),
      ).thenAnswer((_) async => [_page(0, render: 'p0/render.jpg'), _page(1)]);
      when(() => ocr.extractText('p0', null))
          .thenAnswer((_) async => _text('First page'));
      when(() => ocr.extractText('p1', null)).thenThrow(const OcrFailed('p1'));
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('txt keeps stored text and leaves a failed page out', () async {
      final progress = <(int, int)>[];
      final file = await export.txt(
        'd1',
        onProgress: (d, t) => progress.add((d, t)),
      );

      expect(p.basename(file.path), 'Rent_ 11_11.txt');
      expect(file.readAsStringSync(), 'First page');
      expect(progress, [(1, 2), (2, 2)]);
    });

    test('docx is a Word file named after the document', () async {
      final file = await export.docx('d1');

      expect(p.basename(file.path), 'Rent_ 11_11.docx');
      expect(_documentXml(file.readAsBytesSync()), contains('First page'));
    });

    test('searchable PDF pairs each read image with its text', () async {
      final file = await export.searchablePdf('d1');

      expect(p.basename(file.path), 'Rent_ 11_11.pdf');
      expect(file.readAsBytesSync(), [1, 2, 3]);
      expect(builtImages, [
        p.join(root.path, 'p0/render.jpg'),
        p.join(root.path, 'p1/original.jpg'),
      ]);
      expect(builtTexts!.map((t) => t?.text), ['First page', null]);
    });
  });
}
