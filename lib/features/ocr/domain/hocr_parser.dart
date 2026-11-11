import 'ocr_result.dart';

// Tesseract writes the page bbox as left top width height.
final _pageBox = RegExp(r"class='ocr_page'[^>]*?bbox \d+ \d+ (\d+) (\d+)");
final _word = RegExp(
  r"<span class='ocrx_word'[^>]*?title='bbox (\d+) (\d+) (\d+) (\d+); "
  r"x_wconf (\d+)'[^>]*>(.*?)</span>",
  dotAll: true,
);
final _tag = RegExp('<[^>]*>');

/// Words from Tesseract's hOCR, normalized by the `ocr_page` bbox.
List<OcrWord> parseHocrWords(String hocr) {
  final page = _pageBox.firstMatch(hocr);
  if (page == null) throw const FormatException('hOCR has no ocr_page bbox');
  final width = int.parse(page[1]!);
  final height = int.parse(page[2]!);
  return [
    for (final m in _word.allMatches(hocr))
      if (_unescape(m[6]!.replaceAll(_tag, '')).trim() case final text
          when text.isNotEmpty)
        OcrWord(
          text,
          left: int.parse(m[1]!) / width,
          top: int.parse(m[2]!) / height,
          right: int.parse(m[3]!) / width,
          bottom: int.parse(m[4]!) / height,
          confidence: int.parse(m[5]!),
        ),
  ];
}

// The five entities Tesseract's HOcrEscape writes; &amp; last.
String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
