import 'dart:io';

import 'package:cleanleaf/core/platform/clvision.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled DocAligner model matches decisions.md D-11', () {
    final bytes = File(docAlignerAsset).readAsBytesSync();
    expect(
      sha256.convert(bytes).toString(),
      'd1a24adca6ba884cb535d94b98c9c32a6467b6c590efa06868ce5a3bed4eb065',
    );
  });
}
