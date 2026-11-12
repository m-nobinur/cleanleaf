import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../ocr/domain/ocr_result.dart';
import 'plain_text.dart';

const _contentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '</Types>';

const _rels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

// A4 with 2.5 cm margins, in twentieths of a point.
const _section =
    '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
    '<w:pgMar w:top="1418" w:right="1418" w:bottom="1418" w:left="1418" '
    'w:header="709" w:footer="709" w:gutter="0"/></w:sectPr>';

const _pageBreak = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>';

/// A minimal Word document: one paragraph per OCR text block (lines kept as
/// line breaks), a page break between pages. Null pages stay empty.
Uint8List buildDocx(List<OcrResult?> pages) {
  final body = StringBuffer();
  for (final (i, page) in pages.indexed) {
    if (i > 0) body.write(_pageBreak);
    for (final block in textBlocks(page?.text ?? '')) {
      final lines = [
        for (final line in block.split('\n'))
          '<w:t xml:space="preserve">${_xml(line)}</w:t>',
      ];
      body.write('<w:p><w:r>${lines.join('<w:br/>')}</w:r></w:p>');
    }
  }
  final document =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body<w:p/>$_section</w:body></w:document>';
  return ZipEncoder().encodeBytes(
    Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
      ..addFile(ArchiveFile.string('_rels/.rels', _rels))
      ..addFile(ArchiveFile.string('word/document.xml', document)),
  );
}

// XML 1.0 forbids most C0 controls even when escaped.
final _illegal = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F￾￿]');

String _xml(String s) => s
    .replaceAll(_illegal, '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
