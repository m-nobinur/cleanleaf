/// [code] is the Tesseract language string (decisions.md D-13a).
enum OcrLanguage {
  auto('eng+ben'),
  english('eng'),
  bangla('ben');

  const OcrLanguage(this.code);

  final String code;
}
