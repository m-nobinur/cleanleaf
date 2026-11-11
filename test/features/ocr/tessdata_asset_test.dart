import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // tessdata_best e12c65a9 ben, tessdata_fast 87416418 eng (decisions.md D-13a).
  const expected = {
    'ben': '1cd0129288d1f74f6661c35e638e487bd146a66bb732ecd9e011e48dcb0df623',
    'eng': '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2',
  };

  for (final MapEntry(key: language, value: hash) in expected.entries) {
    test('bundled $language.traineddata matches its recorded SHA-256', () {
      final bytes = File('assets/tessdata/$language.traineddata')
          .readAsBytesSync();
      expect(sha256.convert(bytes).toString(), hash);
    });
  }
}
