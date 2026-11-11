import '../domain/ocr_result.dart';

// Tesseract writes the page bbox as left top width height.
final _pageBox = RegExp(r"class='ocr_page'[^>]*?bbox \d+ \d+ (\d+) (\d+)");
final _line = RegExp(
  r"<span class='ocr_(?:line|caption|header|textfloat)'[^>]*?"
  r"""title=["']bbox (\d+) (\d+) (\d+) (\d+)""",
);
final _word = RegExp(
  r"<span class='ocrx_word'[^>]*?title='bbox (\d+) (\d+) (\d+) (\d+); "
  r"x_wconf (\d+)'[^>]*>(.*?)</span>",
  dotAll: true,
);
final _tag = RegExp('<[^>]*>');

typedef _Scale = double Function(String? pixels);

/// Lines and their words from hOCR, normalized by the `ocr_page` bbox. Native
/// engines all return hOCR, so this is the one parser.
List<OcrLine> parseHocrLines(String hocr) {
  final page = _pageBox.firstMatch(hocr);
  if (page == null) throw const FormatException('hOCR has no ocr_page bbox');
  final width = int.parse(page[1]!);
  final height = int.parse(page[2]!);
  double x(String? v) => int.parse(v!) / width;
  double y(String? v) => int.parse(v!) / height;
  final lines = _line.allMatches(hocr).toList();
  return [
    for (final (i, line) in lines.indexed)
      if (_words(
            hocr.substring(
              line.end,
              i + 1 < lines.length ? lines[i + 1].start : null,
            ),
            x,
            y,
          )
          case final words when words.isNotEmpty)
        OcrLine(
          words,
          left: x(line[1]),
          top: y(line[2]),
          right: x(line[3]),
          bottom: y(line[4]),
        ),
  ];
}

List<OcrWord> _words(String hocr, _Scale x, _Scale y) => [
  for (final m in _word.allMatches(hocr))
    if (_unescape(m[6]!.replaceAll(_tag, '')).trim() case final text
        when text.isNotEmpty)
      OcrWord(
        text,
        left: x(m[1]),
        top: y(m[2]),
        right: x(m[3]),
        bottom: y(m[4]),
        confidence: int.parse(m[5]!),
      ),
];

// The five entities Tesseract's HOcrEscape writes; &amp; last.
String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
