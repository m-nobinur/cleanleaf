import 'dart:io';

import 'package:cleanleaf/core/platform/clvision.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'clvision_ocr.dart';

String _sha256(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

void main() {
  test('bundled DocAligner model matches decisions.md D-11', () {
    expect(
      _sha256(docAlignerAsset),
      'd1a24adca6ba884cb535d94b98c9c32a6467b6c590efa06868ce5a3bed4eb065',
    );
  });

  test('bundled PP-OCR models match decisions.md D-64', () {
    expect(
      _sha256(ppOcrDetAsset),
      '9f855811f187f0b26e6b9d712b882d12bd705cea0e038a1ccbf538f5db87ea4b',
    );
    expect(
      _sha256(ppOcrRecAsset),
      'd39a6ccbfb49ffd425203eea26cbddb0f9c99af495d4bb5e4af792859417cd3e',
    );
    expect(
      _sha256(ppOcrDictAsset),
      '546a7e3694634428a2e5a79fcd36abec178e04fcd111a79ede717ea16dd93ebb',
    );
  });
}
