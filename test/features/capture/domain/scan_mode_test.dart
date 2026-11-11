import 'package:cleanleaf/features/capture/domain/document_camera.dart';
import 'package:cleanleaf/features/capture/domain/scan_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses known modes and falls back to document', () {
    expect(ScanMode.parse('receipt'), ScanMode.receipt);
    expect(ScanMode.parse('idCard'), ScanMode.idCard);
    expect(ScanMode.parse('book'), ScanMode.book);
    expect(ScanMode.parse('passport'), ScanMode.passport);
    expect(ScanMode.parse('qrCode'), ScanMode.qrCode);
    expect(ScanMode.parse('barcode'), ScanMode.barcode);
    expect(ScanMode.parse('nope'), ScanMode.document);
    expect(ScanMode.parse(null), ScanMode.document);
  });

  test('only code modes read codes', () {
    expect(ScanMode.qrCode.codeFamily, CodeFamily.matrix);
    expect(ScanMode.barcode.codeFamily, CodeFamily.linear);
    expect(ScanMode.document.codeFamily, isNull);
  });

  test('only http(s) codes are web links', () {
    ScannedCode code(String text) => (format: 'QR Code', text: text);
    expect(code(' https://example.org/a ').webLink?.host, 'example.org');
    expect(code('http://x.io').webLink, isNotNull);
    expect(code('intent://evil#Intent;end').webLink, isNull);
    expect(code('javascript:alert(1)').webLink, isNull);
    expect(code('https://').webLink, isNull);
    expect(code('hello world').webLink, isNull);
  });
}
