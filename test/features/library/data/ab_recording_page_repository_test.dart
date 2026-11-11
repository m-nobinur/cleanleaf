import 'dart:convert';
import 'dart:io';

import 'package:cleanleaf/core/metrics/ab_session.dart';
import 'package:cleanleaf/core/storage/app_database.dart';
import 'package:cleanleaf/core/storage/file_store.dart';
import 'package:cleanleaf/features/library/data/ab_recording_page_repository.dart';
import 'package:cleanleaf/features/library/data/drift_document_repository.dart';
import 'package:cleanleaf/features/library/data/drift_page_repository.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late AppDatabase db;
  late FileStore files;
  late DriftDocumentRepository docs;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ab_test');
    db = AppDatabase(NativeDatabase.memory());
    files = FileStore(() async => Directory('${root.path}/store'));
    docs = DriftDocumentRepository(db, files);
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  AbRecordingPageRepository recorder(AbSession session) =>
      AbRecordingPageRepository(DriftPageRepository(db, files), files, session);

  test('copies the original and render and logs them in order', () async {
    final abDir = Directory('${root.path}/ab');
    var tick = 1000;
    final session = AbSession(
      () async => abDir,
      clock: () => DateTime.fromMillisecondsSinceEpoch(tick++),
    );
    final pages = recorder(session);
    final doc = await docs.create('Doc');

    await session.event('scan_start', {'engine': 'googleMlKit'});
    final page = await pages.add(
      doc.id,
      original: Stream.value([1, 2, 3]),
      detectedCorners: null,
      source: PageSource.googleScanner,
    );
    await pages.saveRender(
      page.id,
      render: Stream.value([4, 5]),
      thumb: Stream.value([6]),
    );
    await session.event('flush', {});

    expect(File('${abDir.path}/${page.id}.original.jpg').readAsBytesSync(), [
      1,
      2,
      3,
    ]);
    expect(File('${abDir.path}/${page.id}.render.jpg').readAsBytesSync(), [
      4,
      5,
    ]);
    final events = File('${abDir.path}/events.jsonl')
        .readAsLinesSync()
        .map((l) => jsonDecode(l) as Map<String, Object?>)
        .toList();
    expect(events.map((e) => e['event']), [
      'scan_start',
      'original',
      'render',
      'flush',
    ]);
    expect(events[1], {
      't': 1001,
      'event': 'original',
      'page': page.id,
      'doc': doc.id,
      'source': 'googleScanner',
      'file': '${page.id}.original.jpg',
    });
  });

  test('a broken session never fails the save', () async {
    final blocker = File('${root.path}/not_a_dir')..writeAsStringSync('x');
    final session = AbSession(() async => Directory('${blocker.path}/ab'));
    final pages = recorder(session);
    final doc = await docs.create('Doc');

    final page = await pages.add(
      doc.id,
      original: Stream.value([1]),
      detectedCorners: null,
    );
    await session.event('flush', {});

    expect(await pages.get(page.id), isNotNull);
  });
}
