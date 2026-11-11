import 'package:cleanleaf/features/capture/domain/scan_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses known modes and falls back to document', () {
    expect(ScanMode.parse('receipt'), ScanMode.receipt);
    expect(ScanMode.parse('idCard'), ScanMode.idCard);
    expect(ScanMode.parse('book'), ScanMode.document);
    expect(ScanMode.parse('nope'), ScanMode.document);
    expect(ScanMode.parse(null), ScanMode.document);
  });
}
