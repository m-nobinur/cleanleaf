import 'dart:async';

import 'package:cleanleaf/core/platform/ocr_api.g.dart';
import 'package:cleanleaf/features/ocr/data/pigeon_ocr_engine.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_language.dart';
import 'package:flutter_test/flutter_test.dart';

// One line, one word, in the shape both engines write.
OcrPage _page(String text, {bool? nonLatin}) => OcrPage(
  text: text,
  hocr:
      "<div class='ocr_page' id='page_1' title='bbox 0 0 200 100'>"
      "<span class='ocr_line' id='line_1_1' title='bbox 20 10 120 30'>"
      "<span class='ocrx_word' id='word_1_1' title='bbox 20 10 120 30; "
      "x_wconf 97'>$text</span></span></div>",
  nonLatin: nonLatin,
);

class _FakeHost extends OcrHostApi {
  _FakeHost(this.pages);

  /// Answers per engine id.
  final Map<String, OcrPage?> pages;
  final calls = <(String, String)>[];
  var cancels = 0;
  var releases = 0;
  Completer<void>? holdFirst;

  @override
  Future<OcrPage?> recognize(
    String engine,
    String imagePath,
    String language,
    int maxLongSide,
  ) async {
    calls.add((engine, language));
    if (calls.length == 1) await holdFirst?.future;
    return pages[engine];
  }

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> release() async => releases++;
}

void main() {
  test('PP-OCR reads English and Auto, Tesseract Bangla', () {
    expect(ocrEngineFor(OcrLanguage.english), ppOcrEngine);
    expect(ocrEngineFor(OcrLanguage.auto), ppOcrEngine);
    expect(ocrEngineFor(OcrLanguage.bangla), tesseractEngine);
  });

  test('stores the engine that read the page, with parsed boxes', () async {
    final host = _FakeHost({ppOcrEngine: _page('Invoice', nonLatin: false)});

    final result = await PigeonOcrEngine(api: host)
        .recognize('/p.jpg', OcrLanguage.english);

    expect(host.calls, [(ppOcrEngine, 'english')]);
    expect(
      [result!.text, result.engine, result.language],
      ['Invoice', ppOcrEngine, OcrLanguage.english],
    );
    final word = result.lines.single.words.single;
    expect(
      [word.left, word.top, word.right, word.bottom, word.confidence],
      [.1, .1, .6, .3, 97],
    );
  });

  test('Auto keeps a Latin page on PP-OCR', () async {
    final host = _FakeHost({ppOcrEngine: _page('Invoice', nonLatin: false)});

    final result = await PigeonOcrEngine(api: host)
        .recognize('/p.jpg', OcrLanguage.auto);

    expect(host.calls, [(ppOcrEngine, 'auto')]);
    expect(result!.engine, ppOcrEngine);
  });

  test('Auto re-reads a non-Latin page with Tesseract eng+ben', () async {
    final host = _FakeHost({
      ppOcrEngine: _page('G0', nonLatin: true),
      tesseractEngine: _page('বাংলা'),
    });

    final result = await PigeonOcrEngine(api: host)
        .recognize('/p.jpg', OcrLanguage.auto);

    expect(host.calls, [(ppOcrEngine, 'auto'), (tesseractEngine, 'auto')]);
    expect(
      [result!.text, result.engine, result.language],
      ['বাংলা', tesseractEngine, OcrLanguage.auto],
    );
  });

  test('explicit English keeps PP-OCR even on a non-Latin page', () async {
    final host = _FakeHost({ppOcrEngine: _page('G0', nonLatin: true)});

    final result = await PigeonOcrEngine(api: host)
        .recognize('/p.jpg', OcrLanguage.english);

    expect(host.calls, [(ppOcrEngine, 'english')]);
    expect(result!.engine, ppOcrEngine);
  });

  test('a cancel during the PP-OCR read skips the Tesseract re-read', () async {
    final host = _FakeHost({
      ppOcrEngine: _page('G0', nonLatin: true),
      tesseractEngine: _page('বাংলা'),
    })..holdFirst = Completer();
    final engine = PigeonOcrEngine(api: host);

    final result = engine.recognize('/p.jpg', OcrLanguage.auto);
    await engine.cancel();
    host.holdFirst!.complete();

    expect(await result, isNull);
    expect(host.calls, [(ppOcrEngine, 'auto')]);
    expect(host.cancels, 1);
  });

  test('a cancelled read returns null', () async {
    final host = _FakeHost({ppOcrEngine: null});

    expect(
      await PigeonOcrEngine(api: host).recognize('/p.jpg', OcrLanguage.auto),
      isNull,
    );
    expect(host.calls, hasLength(1));
  });

  test('release frees the host engines', () async {
    final host = _FakeHost({});

    await PigeonOcrEngine(api: host).release();

    expect(host.releases, 1);
  });
}
