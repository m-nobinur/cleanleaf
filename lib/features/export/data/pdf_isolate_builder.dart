import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../ocr/domain/ocr_result.dart';
import '../domain/export_pdf.dart';

/// Embeds each JPEG as-is: no re-encode, so quality is whatever the capture
/// or enhance step wrote. Page = image aspect fitted inside A4 portrait.
/// With [texts] (one per image) and a TrueType [font], each page also gets an
/// invisible, searchable text layer over its words.
Future<Uint8List> buildPdfBytes(
  List<String> imagePaths, {
  SendPort? progress,
  List<OcrResult?>? texts,
  Uint8List? font,
}) async {
  final doc = pw.Document();
  final textFont = font == null
      ? null
      : PdfTtfFont(doc.document, ByteData.sublistView(font));
  var done = 0;
  for (final (i, path) in imagePaths.indexed) {
    final image = pw.MemoryImage(File(path).readAsBytesSync());
    final scale = _fitScale(image.width!, image.height!);
    final text = texts?[i];
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(image.width! * scale, image.height! * scale),
        margin: pw.EdgeInsets.zero,
        build: (_) => text == null || textFont == null
            ? pw.Image(image, fit: pw.BoxFit.fill)
            : pw.Stack(
                children: [
                  pw.Positioned.fill(
                    child: pw.Image(image, fit: pw.BoxFit.fill),
                  ),
                  pw.Positioned.fill(
                    child: pw.CustomPaint(
                      painter: (canvas, size) =>
                          _drawTextLayer(canvas, size, text, textFont),
                    ),
                  ),
                ],
              ),
      ),
    );
    progress?.send(++done);
  }
  return doc.save();
}

/// Each word is drawn invisibly at its box: the line box sets the size (font
/// ascent to descent), horizontal scaling stretches the word to its box width,
/// and a trailing space keeps words apart when a viewer extracts the text.
void _drawTextLayer(
  PdfGraphics canvas,
  PdfPoint size,
  OcrResult text,
  PdfFont font,
) {
  final extent = font.ascent - font.descent;
  for (final line in text.lines) {
    final fontSize = (line.bottom - line.top) * size.y / extent;
    if (fontSize <= 0) continue;
    // PDF y runs up from the page bottom; descent is negative.
    final baseline = (1 - line.bottom) * size.y - font.descent * fontSize;
    for (final (i, word) in line.words.indexed) {
      if (word.text.isEmpty) continue;
      final natural = font.stringMetrics(word.text).advanceWidth * fontSize;
      final boxWidth = (word.right - word.left) * size.x;
      canvas.drawString(
        font,
        fontSize,
        i == line.words.length - 1 ? word.text : '${word.text} ',
        word.left * size.x,
        baseline,
        mode: PdfTextRenderingMode.invisible,
        scale: natural > 0 && boxWidth > 0 ? boxWidth / natural : null,
      );
    }
  }
}

double _fitScale(int width, int height) {
  final wide = PdfPageFormat.a4.width / width;
  final tall = PdfPageFormat.a4.height / height;
  return wide < tall ? wide : tall;
}

Future<Uint8List> buildPdfInIsolate(
  List<String> imagePaths,
  ExportProgress? onProgress,
) async {
  final port = ReceivePort();
  final sub = port.listen(
    (done) => onProgress?.call(done as int, imagePaths.length),
  );
  final sendPort = port.sendPort; // the closure must not capture the port
  try {
    return await Isolate.run(
      () => buildPdfBytes(imagePaths, progress: sendPort),
    );
  } finally {
    await sub.cancel();
    port.close();
  }
}

/// [font] is the TrueType font for the text layer, loaded on the calling
/// isolate because asset loading isn't available inside the worker.
Future<Uint8List> buildSearchablePdfInIsolate(
  List<String> imagePaths,
  List<OcrResult?> texts,
  Uint8List font,
) => Isolate.run(() => buildPdfBytes(imagePaths, texts: texts, font: font));
