import 'dart:async';
import 'dart:io';

import 'package:cleanleaf/core/storage/file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late FileStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('file_store_test');
    store = FileStore(() async => root);
  });

  tearDown(() => root.delete(recursive: true));

  test(
    'writes into docs/<docId>/<pageId>/ and returns a relative path',
    () async {
      final path = await store.writePageFile(
        'd1',
        'p1',
        PageFile.original,
        Stream.value([1, 2, 3]),
      );

      expect(path, 'docs/d1/p1/original.jpg');
      expect(await (await store.resolve(path)).readAsBytes(), [1, 2, 3]);
    },
  );

  test('failed write keeps the old file and leaves no partial file', () async {
    final path = await store.writePageFile(
      'd1',
      'p1',
      PageFile.render,
      Stream.value([1]),
    );
    final failing = StreamController<List<int>>();
    final write = store.writePageFile(
      'd1',
      'p1',
      PageFile.render,
      failing.stream,
    );
    failing
      ..add([9, 9, 9])
      ..addError(const FileSystemException('disk full'));
    unawaited(failing.close());

    await expectLater(write, throwsA(isA<FileSystemException>()));
    final dir = Directory('${root.path}/docs/d1/p1');
    expect(dir.listSync().map((e) => e.uri.pathSegments.last), ['render.jpg']);
    expect(await (await store.resolve(path)).readAsBytes(), [1]);
  });

  test('deleteDocument removes the whole document folder', () async {
    await store.writePageFile('d1', 'p1', PageFile.original, Stream.value([1]));
    await store.writePageFile('d1', 'p2', PageFile.thumb, Stream.value([2]));
    await store.writePageFile('d2', 'p3', PageFile.original, Stream.value([3]));

    await store.deleteDocument('d1');

    expect(Directory('${root.path}/docs/d1').existsSync(), isFalse);
    expect(Directory('${root.path}/docs/d2').existsSync(), isTrue);
  });
}
