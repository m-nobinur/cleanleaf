import 'dart:io';

import 'package:cleanleaf/features/export/data/pdf_isolate_builder.dart';
import 'package:cleanleaf/features/ocr/data/hocr_parser.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_language.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// pdftotext (poppler) reads the text layer the way a PDF viewer's search does.
final _pdftotext = [
  '/opt/homebrew/bin/pdftotext',
  '/usr/local/bin/pdftotext',
  '/usr/bin/pdftotext',
].where((path) => File(path).existsSync()).firstOrNull;

void main() {
  late Directory root;
  final font = File('assets/fonts/NotoSansBengali-Regular-subset.ttf')
      .readAsBytesSync();

  setUp(() => root = Directory.systemTemp.createTempSync('searchable_pdf'));
  tearDown(() => root.deleteSync(recursive: true));

  // The host Tesseract eng+ben read of a 1400x520 image, plus a line of
  // a glyph the font lacks (中) and a ZWNJ word.
  OcrResult fixtureText() {
    final lines = parseHocrLines(
      File('test/fixtures/ocr/mixed_eng_ben.hocr').readAsStringSync(),
    );
    OcrWord word(String text, double left) => OcrWord(
      text,
      left: left,
      top: .9,
      right: left + .1,
      bottom: .95,
      confidence: 90,
    );
    return OcrResult(
      '',
      lines: [
        ...lines,
        OcrLine(
          [
            word('€5', .05),
            word('中文', .2),
            word('café', .35),
            word('র‌্যাব', .5),
          ],
          left: .05,
          top: .9,
          right: .6,
          bottom: .95,
        ),
      ],
      engine: 'tesseract',
      language: OcrLanguage.auto,
    );
  }

  Future<File> buildFixturePdf() async {
    final image = File(p.join(root.path, 'page.jpg'))
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 1400, height: 520)));
    final bytes = await buildPdfBytes(
      [image.path, image.path],
      texts: [fixtureText(), null],
      font: font,
    );
    return File(p.join(root.path, 'out.pdf'))..writeAsBytesSync(bytes);
  }

  test('English and Bangla words extract from the invisible layer', () async {
    final pdf = await buildFixturePdf();
    final result = Process.runSync(_pdftotext!, [
      '-enc',
      'UTF-8',
      pdf.path,
      '-',
    ]);
    final text = result.stdout as String;

    for (final word in [
      'Invoice',
      'Jerry',
      '"paid"',
      'সোনার',
      'তোমায়',
      'ভালোবাসি।',
      'বিশ্ববিদ্যালয়',
      '২০২৪',
      'café',
      '€5',
      'র‌্যাব',
    ]) {
      expect(text, contains(word));
    }
    expect(text, contains('আমার সোনার বাংলা,'), reason: 'words keep spaces');
    final [first, second] = text.split('\f').take(2).toList();
    expect(first.trim(), isNotEmpty);
    expect(second.trim(), isEmpty, reason: 'a null text adds no layer');
  }, skip: _pdftotext == null ? 'pdftotext not installed' : false);

  test('a word lands on its OCR box', () async {
    final pdf = await buildFixturePdf();
    final html =
        Process.runSync(_pdftotext!, [
              '-bbox',
              '-f',
              '1',
              '-l',
              '1',
              pdf.path,
              '-',
            ]).stdout
            as String;
    final match = RegExp(
      r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">Invoice</word>',
    ).firstMatch(html)!;
    final box = [for (var i = 1; i <= 4; i++) double.parse(match[i]!)];

    // Page = 1400x520 fitted to A4 width; word bbox 64..198, line 58..99.
    const scale = 595.2756 / 1400;
    expect(box[0], closeTo(64 * scale, 1));
    expect(box[2], closeTo(198 * scale, 3));
    expect(box[1], closeTo(58 * scale, 2));
    expect(box[3], closeTo(99 * scale, 2));
  }, skip: _pdftotext == null ? 'pdftotext not installed' : false);
}
