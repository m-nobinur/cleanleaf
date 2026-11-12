import 'dart:io';

import 'package:cleanleaf/features/ocr/data/hocr_parser.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_result.dart';
import 'package:flutter_test/flutter_test.dart';

import 'clvision_ocr.dart';

// Synthetic pages rendered for this test: JetBrains Mono 30 px on 1000x240
// (English) and the bundled Noto Sans Bengali subset 40 px on 1000x300.
List<int> _page(String name) =>
    File('test/fixtures/ocr/ppocr_$name.jpg').readAsBytesSync();

void main() {
  late HostPpOcr ocr;

  setUpAll(() => ocr = HostPpOcr());
  tearDownAll(() => ocr.dispose());

  test('reads English as Latin text with hOCR word boxes', () {
    final page = ocr.read(_page('english'), stopIfNonLatin: true);

    expect(page['non_latin'], isFalse);
    const text = [
      'Invoice 2041 for Cleanleaf document scanning',
      'Total due: \$1,250.00 payable within thirty days',
      'Received with thanks on 12 November 2026',
    ];
    expect(page['text'], text.join('\n'));
    final lines = parseHocrLines(page['hocr'] as String);
    expect(lines.map((l) => l.words.map((w) => w.text).join(' ')), text);
    // Rendered boxes of "Invoice" and "scanning", normalized to the page.
    void near(OcrWord word, double left, double right) {
      expect(word.left, closeTo(left, .02), reason: word.text);
      expect(word.right, closeTo(right, .02), reason: word.text);
      expect(word.top, lessThan(.2), reason: word.text);
      expect(word.bottom, greaterThan(.29), reason: word.text);
      expect(word.confidence, inInclusiveRange(80, 100), reason: word.text);
    }

    near(lines[0].words.first, .06, .186);
    near(lines[0].words.last, .708, .852);
    for (final line in lines) {
      for (final (a, b) in [
        for (var i = 1; i < line.words.length; i++)
          (line.words[i - 1], line.words[i]),
      ]) {
        expect(
          a.right,
          lessThanOrEqualTo(b.left),
          reason: '${a.text} ${b.text}',
        );
      }
      expect(line.left, greaterThanOrEqualTo(0));
      expect(line.right, lessThanOrEqualTo(1));
    }
  });

  test('flags Bangla as non-Latin, and can stop as soon as it knows', () {
    final full = ocr.read(_page('bangla'));
    final stopped = ocr.read(_page('bangla'), stopIfNonLatin: true);

    expect(full['non_latin'], isTrue);
    expect(full['flagged'], greaterThan(.25));
    expect(stopped['non_latin'], isTrue);
    expect(
      (stopped['lines'] as List).length,
      lessThan((full['lines'] as List).length),
    );
  });

  test('a set cancel flag stops the read', () {
    expect(
      () => ocr.read(_page('english'), cancelled: true),
      throwsA(
        isA<ClvOcrException>().having((e) => e.status, 'status', clvCancelled),
      ),
    );
  });
}
