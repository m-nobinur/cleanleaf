import 'package:cleanleaf/features/library/domain/default_title.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats as Scan YYYY-MM-DD HH.mm with zero padding', () {
    expect(
      defaultDocumentTitle(DateTime(2026, 3, 5, 7, 4)),
      'Scan 2026-03-05 07.04',
    );
  });
}
