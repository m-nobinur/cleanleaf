import '../../ocr/domain/ocr_result.dart';

/// The engine separates text blocks with a blank line; each block keeps its
/// line breaks.
List<String> textBlocks(String text) => [
  for (final block in text.split(RegExp(r'\n\s*\n')))
    if (block.trim().isNotEmpty) block.trim(),
];

/// The document's text, page after page, separated by a blank line. Null
/// pages (not readable) are left out.
String plainText(List<OcrResult?> pages) => [
  for (final page in pages)
    if (page != null && textBlocks(page.text).isNotEmpty)
      textBlocks(page.text).join('\n\n'),
].join('\n\n');
