import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // tessdata_best commit e12c65a9, ben and eng (decisions.md D-13a).
  const expected = {
    'ben': '1cd0129288d1f74f6661c35e638e487bd146a66bb732ecd9e011e48dcb0df623',
    'eng': '8280aed0782fe27257a68ea10fe7ef324ca0f8d85bd2fd145d1c2b560bcb66ba',
  };

  for (final MapEntry(key: language, value: hash) in expected.entries) {
    test('bundled $language.traineddata matches its recorded SHA-256', () {
      final bytes = File('assets/tessdata/$language.traineddata')
          .readAsBytesSync();
      expect(sha256.convert(bytes).toString(), hash);
    });
  }
}
