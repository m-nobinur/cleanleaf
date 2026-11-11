import 'dart:io';

import 'package:cleanleaf/core/storage/file_store.dart';
import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/features/editor/presentation/editor_providers.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('pageImageProvider decodes the stored original at its size', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('editor_image');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/original.jpg')
        .writeAsBytesSync(img.encodeJpg(img.Image(width: 30, height: 20)));
    final container = ProviderContainer(
      overrides: [
        fileStoreProvider.overrideWithValue(FileStore(() async => root)),
      ],
    );
    addTearDown(container.dispose);
    // Real file IO and decoding only complete outside the fake-async zone.
    final page = await tester.runAsync(() async {
      final provider = pageImageProvider('original.jpg');
      final subscription = container.listen(provider, (_, _) {});
      try {
        return await container.read(provider.future);
      } finally {
        subscription.close();
      }
    });

    expect(page!.size, const Size(30, 20));
    expect(page.image, isA<ResizeImage>());
  });
}
