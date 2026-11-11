import 'dart:async';
import 'dart:io';

import 'package:cleanleaf/core/storage/app_database.dart';
import 'package:cleanleaf/core/storage/file_store.dart';
import 'package:cleanleaf/features/library/data/drift_document_repository.dart';
import 'package:cleanleaf/features/library/data/drift_page_repository.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/ocr/data/drift_ocr_repository.dart';
import 'package:cleanleaf/features/ocr/data/ocr_queue.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_engine.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_language.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_repository.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_result.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each recognize() waits until the test finishes or fails it; cancel()
/// completes it with null like Tesseract's stop().
class FakeOcrEngine implements OcrEngine {
  final calls = <(String, OcrLanguage)>[];
  final _running = <Completer<OcrResult?>>[];
  var cancels = 0;

  @override
  Future<OcrResult?> recognize(String imagePath, OcrLanguage language) {
    calls.add((imagePath, language));
    return (_running..add(Completer())).last.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    for (final c in _running) {
      if (!c.isCompleted) c.complete(null);
    }
  }

  void finish(String text, OcrLanguage language) => _running.last.complete(
    OcrResult(
      text,
      lines: [
        OcrLine(
          [
            OcrWord(
              text,
              left: .1,
              top: .2,
              right: .3,
              bottom: .4,
              confidence: 90,
            ),
          ],
          left: .1,
          top: .2,
          right: .3,
          bottom: .4,
        ),
      ],
      engine: 'fake',
      language: language,
    ),
  );

  void fail() => _running.last.completeError(StateError('engine crashed'));
}

void main() {
  late Directory root;
  late AppDatabase db;
  late DriftDocumentRepository docs;
  late DriftPageRepository pages;
  late FakeOcrEngine engine;
  late OcrQueue queue;
  late DriftOcrRepository ocr;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ocr_test');
    db = AppDatabase(NativeDatabase.memory());
    final files = FileStore(() async => root);
    docs = DriftDocumentRepository(db, files);
    pages = DriftPageRepository(db, files);
    engine = FakeOcrEngine();
    queue = OcrQueue(db, files, engine);
    ocr = DriftOcrRepository(db, queue);
  });

  tearDown(() async {
    await queue.stop();
    await db.close();
    await root.delete(recursive: true);
  });

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 500 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(condition(), isTrue, reason: 'condition not reached');
  }

  Future<DocumentPage> renderedPage(String docId) async {
    final page = await pages.add(
      docId,
      original: Stream.value([1]),
      detectedCorners: null,
    );
    await pages.saveRender(
      page.id,
      render: Stream.value([2]),
      thumb: Stream.value([3]),
    );
    return page;
  }

  Future<OcrStatus?> status(String pageId) => ocr.watchStatus(pageId).first;

  test(
    'reads a saved render in the background and stores the result',
    () async {
      final doc = await docs.create('A');
      final page = await renderedPage(doc.id);
      final statuses = <OcrStatus?>[];
      final sub = ocr.watchStatus(page.id).listen(statuses.add);

      await queue.start();
      await until(() => engine.calls.length == 1);
      expect(
        engine.calls.single.$1,
        '${root.path}/docs/${doc.id}/${page.id}/render.jpg',
      );
      expect(engine.calls.single.$2, OcrLanguage.auto);
      expect(await ocr.watchReadingDocumentIds().first, {doc.id});

      engine.finish('Hello', OcrLanguage.auto);
      await until(() => statuses.lastOrNull == OcrStatus.done);
      await sub.cancel();

      expect(
        statuses,
        containsAllInOrder([
          OcrStatus.pending,
          OcrStatus.running,
          OcrStatus.done,
        ]),
      );
      final row = await (db.select(
        db.pages,
      )..where((t) => t.id.equals(page.id))).getSingle();
      expect(row.ocrEngine, 'fake');
      expect(row.ocrLanguage, 'auto');
      final result = await ocr.extractText(page.id, OcrLanguage.auto);
      expect(result.text, 'Hello');
      expect(result.engine, 'fake');
      final [line] = result.lines;
      expect(
        [line.words.single.text, line.words.single.right, line.bottom],
        ['Hello', .3, .4],
      );
      expect(engine.calls, hasLength(1), reason: 'stored result reused');
      expect(await ocr.watchReadingDocumentIds().first, isEmpty);
    },
  );

  test(
    'skips uncropped camera pages; reads Google scans from the original',
    () async {
      final doc = await docs.create('A');
      final camera = await pages.add(
        doc.id,
        original: Stream.value([1]),
        detectedCorners: null,
      );
      final google = await pages.add(
        doc.id,
        original: Stream.value([1]),
        detectedCorners: null,
        source: PageSource.googleScanner,
      );
      expect(google.ocrStatus, OcrStatus.pending);

      await queue.start();
      await until(() => engine.calls.length == 1);

      expect(engine.calls.single.$1, endsWith('${google.id}/original.jpg'));
      expect(await status(camera.id), isNull);
    },
  );

  test('start resumes a page left running by a dead process', () async {
    final doc = await docs.create('A');
    final page = await renderedPage(doc.id);
    await (db.update(db.pages)..where((t) => t.id.equals(page.id))).write(
      PagesCompanion(ocrStatus: Value(OcrStatus.running.name)),
    );

    await queue.start();

    await until(() => engine.calls.length == 1);
  });

  test('deleting a page mid-read cancels the engine', () async {
    final doc = await docs.create('A');
    final page = await renderedPage(doc.id);
    final next = await renderedPage(doc.id);
    await queue.start();
    await until(() => engine.calls.length == 1);
    final first = engine.calls.single.$1.contains(page.id) ? page : next;

    await pages.delete(first.id);

    await until(() => engine.cancels == 1 && engine.calls.length == 2);
  });

  test(
    'a new render mid-read cancels, drops the stale text and reads again',
    () async {
      final doc = await docs.create('A');
      final page = await renderedPage(doc.id);
      await queue.start();
      await until(() => engine.calls.length == 1);

      await pages.saveRender(
        page.id,
        render: Stream.value([4]),
        thumb: Stream.value([5]),
      );
      await until(() => engine.calls.length == 2);
      expect(engine.cancels, 1);
      engine.finish('Fresh', OcrLanguage.auto);

      expect((await ocr.extractText(page.id, OcrLanguage.auto)).text, 'Fresh');
    },
  );

  test('a failed read is stored as failed and retried on request', () async {
    final doc = await docs.create('A');
    final page = await renderedPage(doc.id);
    await queue.start();
    await until(() => engine.calls.length == 1);
    engine.fail();
    await until(() => engine.calls.length == 1);
    await ocr.watchStatus(page.id).firstWhere((s) => s == OcrStatus.failed);

    final result = ocr.extractText(page.id, OcrLanguage.auto);
    await until(() => engine.calls.length == 2);
    engine.fail();

    await expectLater(result, throwsA(isA<OcrFailed>()));
  });

  test(
    'extractText in another language jumps ahead of background pages',
    () async {
      final doc = await docs.create('A');
      final busy = await renderedPage(doc.id);
      final waiting = await renderedPage(doc.id);
      final wanted = await renderedPage(doc.id);
      await queue.start();
      await until(() => engine.calls.length == 1);
      final running = [
        busy,
        waiting,
        wanted,
      ].firstWhere((p) => engine.calls.single.$1.contains(p.id));
      final target = running == wanted ? busy : wanted;

      final result = ocr.extractText(target.id, OcrLanguage.bangla);
      engine.finish('first', OcrLanguage.auto);
      await until(() => engine.calls.length == 2);

      expect(engine.calls.last, (
        '${root.path}/docs/${doc.id}/${target.id}/render.jpg',
        OcrLanguage.bangla,
      ));
      engine.finish('বাংলা', OcrLanguage.bangla);
      final read = await result;
      expect([read.text, read.language], ['বাংলা', OcrLanguage.bangla]);
    },
  );

  group('search', () {
    Future<void> setText(String pageId, String text) =>
        (db.update(db.pages)..where((t) => t.id.equals(pageId))).write(
          PagesCompanion(ocrText: Value(text)),
        );

    Future<List<String>> titles(String query) async =>
        (await ocr.watchSearch(query).first).map((d) => d.title).toList();

    test(
      'matches titles and page text, every term, Bangla substrings',
      () async {
        final invoice = await docs.create('Invoice March');
        final letter = await docs.create('Letter');
        await docs.create('Empty');
        await setText(
          (await renderedPage(invoice.id)).id,
          'Total due 1,250 Taka',
        );
        await setText(
          (await renderedPage(letter.id)).id,
          'ঢাকা বিশ্ববিদ্যালয় ২০২৪ সালের রিপোর্ট',
        );

        expect(await titles('invoice'), ['Invoice March']);
        expect(await titles('TAKA'), ['Invoice March']);
        expect(await titles('march taka'), ['Invoice March']);
        expect(await titles('march রিপোর্ট'), isEmpty);
        expect(await titles('বিদ্যালয়'), ['Letter']);
        expect(await titles('সাল'), ['Letter']);
        expect(await titles('  '), hasLength(3));
      },
    );

    test('treats LIKE wildcards in the query literally', () async {
      final doc = await docs.create('Discount');
      await setText((await renderedPage(doc.id)).id, '50% off');

      expect(await titles('%'), ['Discount']);
      expect(await titles('5_'), isEmpty);
      expect(await titles(r'\'), isEmpty);
    });

    test('search timing over 3000 pages', () async {
      const text =
          'Invoice total due ঢাকা বিশ্ববিদ্যালয় সালের রিপোর্ট আমার সোনার বাংলা ';
      await db.batch((b) {
        for (var d = 0; d < 1000; d++) {
          b.insert(
            db.documents,
            DocumentsCompanion.insert(
              id: 'd$d',
              title: 'Doc $d',
              createdAt: d,
              updatedAt: d,
            ),
          );
          for (var p = 0; p < 3; p++) {
            b.insert(
              db.pages,
              PagesCompanion.insert(
                id: 'd$d-$p',
                documentId: 'd$d',
                pageIndex: p,
                originalPath: 'x',
                corners: '[]',
                source: 'camera',
                anchors: '[]',
                rotation: 0,
                filter: 'original',
                filterParams: '{}',
                ocrText: Value('${text * 30} page $d-$p'),
              ),
            );
          }
        }
      });
      // Each query runs once: drift reuses a stream it has just served.
      for (final query in [
        'বিদ্যালয়',
        'page 999-2',
        'nomatch',
        'invoice ঢাকা',
      ]) {
        final watch = Stopwatch()..start();
        final hits = await titles(query);
        // ignore: avoid_print
        print(
          'search "$query": ${hits.length} hits in ${watch.elapsedMilliseconds} ms',
        );
      }
    });
  });
}
