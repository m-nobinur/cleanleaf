import 'package:cleanleaf/features/export/domain/pdf_file_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replaces characters the share sheet rejects', () {
    expect(pdfFileName('Scan 11/11: "rent"?'), 'Scan 11_11_ _rent_');
  });

  test('falls back when nothing usable is left', () {
    expect(pdfFileName('  '), 'Scan');
    expect(pdfFileName('...'), 'Scan');
  });

  test('caps the length', () {
    expect(pdfFileName('a' * 200).length, 80);
  });
}
