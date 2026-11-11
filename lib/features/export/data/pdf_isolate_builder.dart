import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/export_pdf.dart';

/// Embeds each JPEG as-is: no re-encode, so quality is whatever the capture
/// or enhance step wrote. Page = image aspect fitted inside A4 portrait.
Future<Uint8List> buildPdfBytes(
  List<String> imagePaths, {
  SendPort? progress,
}) async {
  final doc = pw.Document();
  var done = 0;
  for (final path in imagePaths) {
    final image = pw.MemoryImage(File(path).readAsBytesSync());
    final scale = _fitScale(image.width!, image.height!);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(image.width! * scale, image.height! * scale),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ),
    );
    progress?.send(++done);
  }
  return doc.save();
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
