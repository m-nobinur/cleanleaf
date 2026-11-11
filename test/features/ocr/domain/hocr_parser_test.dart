import 'dart:io';

import 'package:cleanleaf/features/ocr/domain/hocr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Host Tesseract 5.5.3, bundled eng+ben traineddata, --psm 3, 1400x520 image.
  final hocr = File('test/fixtures/ocr/mixed_eng_ben.hocr').readAsStringSync();

  test('reads every word with boxes normalized to the page', () {
    final words = parseHocrWords(hocr);

    expect(words, hasLength(24));
    final first = words.first;
    expect(first.text, 'Invoice');
    expect(first.left, closeTo(64 / 1400, 1e-9));
    expect(first.top, closeTo(58 / 520, 1e-9));
    expect(first.right, closeTo(198 / 1400, 1e-9));
    expect(first.bottom, closeTo(90 / 520, 1e-9));
    expect(first.confidence, 96);
  });

  test('decodes hOCR escapes and keeps Bangla graphemes intact', () {
    final texts = parseHocrWords(hocr).map((w) => w.text).toList();

    expect(texts, containsAllInOrder(['&', '<Ltd>', '"paid"', "it's"]));
    expect(
      texts,
      containsAllInOrder([
        'আমার',
        'সোনার',
        'বিশ্ববিদ্যালয়',
        '২০২৪',
        'রিপোর্ট',
      ]),
    );
  });

  test('handles word attributes, font tags and empty words', () {
    const page = '''
<div class='ocr_page' id='page_1' title='image ""; bbox 0 0 200 100; ppageno 0'>
 <span class='ocrx_word' id='word_1_1' title='bbox 10 20 50 40; x_wconf 71' lang='ben' dir='ltr'><strong>ঢাকা</strong></span>
 <span class='ocrx_word' id='word_1_2' title='bbox 60 20 70 40; x_wconf 0'> </span>
</div>''';

    final [word] = parseHocrWords(page);

    expect(word.text, 'ঢাকা');
    expect(
      [word.left, word.top, word.right, word.bottom],
      [0.05, 0.2, 0.25, 0.4],
    );
    expect(word.confidence, 71);
  });

  test('rejects hOCR without a page', () {
    expect(() => parseHocrWords('<html></html>'), throwsFormatException);
  });
}
