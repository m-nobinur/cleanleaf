import 'dart:io';

import 'package:cleanleaf/features/ocr/data/hocr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Host Tesseract 5.5.3, bundled eng+ben traineddata, --psm 3, 1400x520 image.
  final hocr = File('test/fixtures/ocr/mixed_eng_ben.hocr').readAsStringSync();

  test('reads lines and words with boxes normalized to the page', () {
    final lines = parseHocrLines(hocr);

    expect(lines.map((l) => l.words.length), [7, 6, 6, 5]);
    final line = lines.first;
    expect(
      [line.left, line.top, line.right, line.bottom],
      [64 / 1400, 58 / 520, 793 / 1400, 99 / 520],
    );
    final word = line.words.first;
    expect(word.text, 'Invoice');
    expect(
      [word.left, word.top, word.right, word.bottom],
      [64 / 1400, 58 / 520, 198 / 1400, 90 / 520],
    );
    expect(word.confidence, 96);
  });

  test('decodes hOCR escapes and keeps Bangla graphemes intact', () {
    final [english, _, bangla, _] = parseHocrLines(hocr);

    expect(english.words.map((w) => w.text), [
      'Invoice',
      '#42:',
      'Tom',
      '&',
      'Jerry',
      '<Ltd>',
      '"paid"',
    ]);
    expect(bangla.words.map((w) => w.text), [
      'আমার',
      'সোনার',
      'বাংলা,',
      'আমি',
      'তোমায়',
      'ভালোবাসি।',
    ]);
  });

  test('handles word attributes, font tags and empty words and lines', () {
    const page = '''
<div class='ocr_page' id='page_1' title='image ""; bbox 0 0 200 100; ppageno 0'>
 <span class='ocr_header' id='line_1_1' title="bbox 10 20 70 40; baseline 0 0">
  <span class='ocrx_word' id='word_1_1' title='bbox 10 20 50 40; x_wconf 71' lang='ben' dir='ltr'><strong>ঢাকা</strong></span>
  <span class='ocrx_word' id='word_1_2' title='bbox 60 20 70 40; x_wconf 0'> </span>
 </span>
 <span class='ocr_line' id='line_1_2' title="bbox 0 50 10 60">
  <span class='ocrx_word' id='word_1_3' title='bbox 0 50 10 60; x_wconf 0'></span>
 </span>
</div>''';

    final [line] = parseHocrLines(page);
    final [word] = line.words;

    expect(word.text, 'ঢাকা');
    expect(
      [word.left, word.top, word.right, word.bottom],
      [0.05, 0.2, 0.25, 0.4],
    );
    expect(word.confidence, 71);
    expect(line.right, 0.35);
  });

  test('rejects hOCR without a page', () {
    expect(() => parseHocrLines('<html></html>'), throwsFormatException);
  });
}
