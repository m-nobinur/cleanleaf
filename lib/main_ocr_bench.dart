import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/platform/ocr_api.g.dart';
import 'core/storage/app_database.dart';
import 'core/storage/file_store.dart';
import 'features/enhance/data/native_page_renderer.dart';
import 'features/library/data/drift_document_repository.dart';
import 'features/library/data/drift_page_repository.dart';
import 'features/library/domain/document_page.dart';
import 'features/ocr/data/drift_ocr_repository.dart';
import 'features/ocr/data/hocr_parser.dart';
import 'features/ocr/data/ocr_queue.dart';
import 'features/ocr/data/pigeon_ocr_engine.dart';
import 'features/ocr/domain/ocr_language.dart';

// OCR on real pages (T-030): push `ocr/pages.json` and its images to the app's
// external files dir, run with -t, read `adb logcat -s flutter:I` until
// `CLBENCH DONE`, then pull `ocr/out/` (renders and recognized text).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A drawn frame keeps the activity visibly in the foreground during the run.
  runApp(
    const Center(
      child: Text('OCR bench running', textDirection: TextDirection.ltr),
    ),
  );
  final heartbeat = Timer.periodic(
    const Duration(seconds: 5),
    (_) => _log('heartbeat rss=${ProcessInfo.currentRss >> 20} MB'),
  );
  try {
    await _run();
  } catch (e, stack) {
    debugPrint('CLBENCH FAILED $e\n$stack');
  } finally {
    heartbeat.cancel();
    debugPrint('CLBENCH DONE');
  }
}

void _log(String line) => debugPrint('CLBENCH $line');

final _pageSize = RegExp(r"class='ocr_page'[^>]*?bbox \d+ \d+ (\d+) (\d+)");

Future<void> _run() async {
  final dir = p.join((await getExternalStorageDirectory())!.path, 'ocr');
  final out = Directory(p.join(dir, 'out'))..createSync(recursive: true);
  final manifest = File(p.join(dir, 'pages.json'));
  for (var i = 0; i < 300 && !manifest.existsSync(); i++) {
    if (i == 0) _log('waiting for pages.json in $dir');
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  // Let a running adb push finish writing the images.
  await Future<void>.delayed(const Duration(seconds: 5));
  final pages = (jsonDecode(manifest.readAsStringSync()) as List<Object?>)
      .cast<Map<String, Object?>>();
  final api = OcrHostApi();
  final watch = Stopwatch()..start();
  _log('cpus ${Platform.numberOfProcessors} pages ${pages.length}');
  final renders = <String>[];
  for (final page in pages) {
    final name = page['name']! as String;
    final [tl, tr, br, bl] = [
      for (final c in page['corners']! as List<Object?>)
        if ((c! as List<Object?>).cast<num>() case [final x, final y])
          (x: x.toDouble(), y: y.toDouble()),
    ];
    watch.reset();
    final jpeg = await const NativePageRenderer().render(
      p.join(dir, page['file']! as String),
      (topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl),
      0,
      PageFilter.enhancedColor,
      const {},
    );
    final render = File(p.join(out.path, '$name.jpg'))..writeAsBytesSync(jpeg);
    renders.add(render.path);
    _log('render $name ${jpeg.length} B in ${watch.elapsedMilliseconds} ms');
    for (final language
        in (page['languages']! as List<Object?>).cast<String>()) {
      // The repeat at full size is warm; the first includes engine init.
      for (final (run, maxLongSide) in [0, 2000, 0].indexed) {
        _log('step ocr $name lang=$language max=$maxLongSide run=$run start');
        watch.reset();
        final result = await api.recognize(
          'tesseract',
          render.path,
          language,
          maxLongSide,
        );
        final ms = watch.elapsedMilliseconds;
        final size = _pageSize.firstMatch(result!.hocr)!;
        final words = parseHocrLines(result.hocr)
            .fold(0, (n, line) => n + line.words.length);
        if (run < 2) {
          File(p.join(out.path, '$name.$language.$maxLongSide.txt'))
              .writeAsStringSync(result.text);
        }
        _log(
          'ocr $name lang=$language max=$maxLongSide run=$run '
          'image=${size[1]}x${size[2]} $ms ms words=$words '
          'chars=${result.text.length} maxRss=${ProcessInfo.maxRss >> 20} MB',
        );
      }
    }
  }
  _log('step cancel start');
  await _cancelLatency(api, renders.last);
  _log('step queue start');
  await _queueEndToEnd(renders.first);
  _log('step search start');
  await _searchTiming();
}

Future<void> _cancelLatency(OcrHostApi api, String image) async {
  final read = api.recognize('tesseract', image, 'auto', 0);
  await Future<void>.delayed(const Duration(seconds: 3));
  final watch = Stopwatch()..start();
  await api.cancel();
  final result = await read;
  _log(
    'cancel after 3 s: returned in ${watch.elapsedMilliseconds} ms, '
    'cancelled=${result == null}',
  );
}

Future<void> _queueEndToEnd(String render) async {
  final root = await Directory(
    p.join((await getTemporaryDirectory()).path, 'ocr_queue'),
  ).create(recursive: true);
  final db = AppDatabase(NativeDatabase.memory());
  final files = FileStore(() async => root);
  final pages = DriftPageRepository(db, files);
  final queue = OcrQueue(db, files, PigeonOcrEngine('tesseract'));
  final ocr = DriftOcrRepository(db, queue);
  final doc = await DriftDocumentRepository(db, files).create('bench');
  final page = await pages.add(
    doc.id,
    original: File(render).openRead(),
    detectedCorners: null,
  );
  final statuses = <OcrStatus?>[];
  final sub = ocr.watchStatus(page.id).listen(statuses.add);
  final watch = Stopwatch()..start();
  await queue.start();
  await pages.saveRender(
    page.id,
    render: File(render).openRead(),
    thumb: Stream.value(const [0]),
  );
  final auto = await ocr.extractText(page.id, OcrLanguage.auto);
  _log(
    'queue auto ${watch.elapsedMilliseconds} ms engine=${auto.engine} '
    'lines=${auto.lines.length} chars=${auto.text.length} statuses=$statuses',
  );
  watch.reset();
  final english = await ocr.extractText(page.id, OcrLanguage.english);
  final term = english.text
      .split(RegExp(r'\s+'))
      .firstWhere((w) => w.length > 4);
  final hits = (await ocr.watchSearch(term).first).length;
  _log(
    'queue english ${watch.elapsedMilliseconds} ms '
    'chars=${english.text.length} search "$term" hits=$hits',
  );
  await sub.cancel();
  await queue.stop();
  await db.close();
  await root.delete(recursive: true);
}

Future<void> _searchTiming() async {
  final db = AppDatabase(NativeDatabase.memory());
  final ocr = DriftOcrRepository(
    db,
    OcrQueue(
      db,
      FileStore(() async => Directory.systemTemp),
      PigeonOcrEngine('none'),
    ),
  );
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
      for (var i = 0; i < 3; i++) {
        b.insert(
          db.pages,
          PagesCompanion.insert(
            id: 'd$d-$i',
            documentId: 'd$d',
            pageIndex: i,
            originalPath: 'x',
            corners: '[]',
            source: 'camera',
            anchors: '[]',
            rotation: 0,
            filter: 'original',
            filterParams: '{}',
            ocrText: Value('${text * 30} page $d-$i'),
          ),
        );
      }
    }
  });
  for (final query in ['বিদ্যালয়', 'page 999-2', 'nomatch', 'invoice ঢাকা']) {
    final watch = Stopwatch()..start();
    final hits = (await ocr.watchSearch(query).first).length;
    _log(
      'search "$query" 3000 pages: $hits hits in ${watch.elapsedMilliseconds} ms',
    );
  }
  await db.close();
}
