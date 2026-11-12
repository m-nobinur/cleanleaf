import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/licenses/third_party_licenses.dart';
import 'core/platform/clvision.dart';
import 'core/platform/ocr_api.g.dart';
import 'core/storage/storage_providers.dart';
import 'features/enhance/data/enhance_providers.dart';
import 'features/export/data/export_providers.dart';
import 'features/export/domain/export_text.dart';
import 'features/gallery_import/data/detect_still_quad.dart';
import 'features/library/data/library_providers.dart';
import 'features/library/domain/document_page.dart';
import 'features/ocr/data/ocr_providers.dart';
import 'features/ocr/data/pigeon_ocr_engine.dart';
import 'features/ocr/domain/ocr_engine.dart';
import 'features/ocr/domain/ocr_language.dart';
import 'features/ocr/domain/ocr_result.dart';

// Release probe for UI screenshots (T-036): when the library is empty, turns
// the real photos in <external files>/seed/ into rendered documents the way
// Save does, then runs the real app. "Lease agreement__2.jpg" is page 2 of
// "Lease agreement". Logs CLSEED lines and a final CLSEED DONE.
// T-031: background OCR starts [_ocrDelay] after launch (time to capture the
// "Reading text…" chip), logs CLOCR DONE when every page is read, then writes
// each document as searchable PDF, .docx and .txt to <external files>/export/
// and logs CLOCR EXPORTED.
// T-038: logs each host read (engine, time, non-Latin verdict), each page's
// routed read (engine, time, peak RSS) and the RSS once the queue has released
// its engine.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();
  final container = ProviderContainer(
    overrides: [
      ocrEngineProvider.overrideWithValue(
        _LoggedOcrEngine(PigeonOcrEngine(api: _LoggedOcrHost())),
      ),
    ],
  );
  try {
    await _seed(container);
  } catch (e) {
    debugPrint('CLSEED ERROR $e');
  }
  debugPrint('CLSEED DONE');
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CleanleafApp(),
    ),
  );
  try {
    await _readAndExport(container);
  } catch (e) {
    debugPrint('CLOCR ERROR $e');
  }
}

const _ocrDelay = Duration(seconds: 45);

Future<void> _readAndExport(ProviderContainer container) async {
  await Future<void>.delayed(_ocrDelay);
  debugPrint('CLOCR START rss=${ProcessInfo.currentRss >> 20} MB');
  final started = DateTime.now();
  await container.read(ocrQueueProvider).start();
  await container
      .read(ocrRepositoryProvider)
      .watchReadingDocumentIds()
      .firstWhere((ids) => ids.isEmpty);
  debugPrint('CLOCR DONE in ${DateTime.now().difference(started).inSeconds} s');

  final export = Directory(
    p.join((await getExternalStorageDirectory())!.path, 'export'),
  );
  final exporter = container.read(exportTextProvider);
  final toExternal = ExportText(
    documents: exporter.documents,
    pages: exporter.pages,
    ocr: exporter.ocr,
    resolve: exporter.resolve,
    outputDir: () async => export,
    buildSearchablePdf: exporter.buildSearchablePdf,
  );
  final pages = container.read(pageRepositoryProvider);
  for (final document
      in await container.read(documentRepositoryProvider).watchAll().first) {
    for (final page in await pages.getByDocument(document.id)) {
      debugPrint(
        'CLOCR page "${document.title}" ${page.id} ${page.ocrStatus?.name}',
      );
    }
    for (final file in [
      await toExternal.searchablePdf(document.id),
      await toExternal.docx(document.id),
      await toExternal.txt(document.id),
    ]) {
      debugPrint('CLOCR export ${file.path} ${file.lengthSync()} B');
    }
  }
  debugPrint('CLOCR EXPORTED');
}

Future<void> _seed(ProviderContainer container) async {
  final documents = container.read(documentRepositoryProvider);
  if ((await documents.watchAll().first).isNotEmpty) {
    debugPrint('CLSEED kept existing library');
    return;
  }
  final dir = Directory(
    p.join((await getExternalStorageDirectory())!.path, 'seed'),
  );
  final photos =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  await loadDocAligner();
  final pages = container.read(pageRepositoryProvider);
  final renderer = container.read(pageRendererProvider);
  final files = container.read(fileStoreProvider);
  final ids = <String, String>{};
  for (final photo in photos) {
    final title = p.basenameWithoutExtension(photo.path).split('__').first;
    final docId = ids[title] ??= (await documents.create(title)).id;
    final page = await pages.add(
      docId,
      original: photo.openRead(),
      detectedCorners: await detectStillQuad(photo.path),
      source: PageSource.gallery,
    );
    final original = (await files.resolve(page.originalPath)).path;
    final render = await renderer.render(
      original,
      page.corners,
      page.rotation,
      page.filter,
      page.filterParams,
    );
    await pages.saveRender(
      page.id,
      render: Stream.value(render),
      thumb: Stream.value(await renderer.thumbnail(render)),
    );
    debugPrint('CLSEED page "$title" ${p.basename(photo.path)}');
  }
}

class _LoggedOcrEngine implements OcrEngine {
  _LoggedOcrEngine(this._engine);

  final OcrEngine _engine;

  @override
  Future<OcrResult?> recognize(String imagePath, OcrLanguage language) async {
    var peak = ProcessInfo.currentRss;
    final sampler = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => peak = max(peak, ProcessInfo.currentRss),
    );
    final watch = Stopwatch()..start();
    try {
      final result = await _engine.recognize(imagePath, language);
      debugPrint(
        'CLOCR read ${p.basename(p.dirname(imagePath))} ${language.name} '
        'engine=${result?.engine} ${watch.elapsedMilliseconds} ms '
        'words=${result?.lines.fold(0, (n, l) => n + l.words.length)} '
        'peakRss=${peak >> 20} MB maxRss=${ProcessInfo.maxRss >> 20} MB',
      );
      return result;
    } finally {
      sampler.cancel();
    }
  }

  @override
  Future<void> cancel() => _engine.cancel();

  @override
  Future<void> release() async {
    await _engine.release();
    debugPrint('CLOCR released rss=${ProcessInfo.currentRss >> 20} MB');
  }
}

class _LoggedOcrHost extends OcrHostApi {
  @override
  Future<OcrPage?> recognize(
    String engine,
    String imagePath,
    String language,
    int maxLongSide,
  ) async {
    final watch = Stopwatch()..start();
    final page = await super.recognize(
      engine,
      imagePath,
      language,
      maxLongSide,
    );
    debugPrint(
      'CLOCR host ${p.basename(p.dirname(imagePath))} $language '
      'engine=$engine ${watch.elapsedMilliseconds} ms '
      'nonLatin=${page?.nonLatin} chars=${page?.text.length}',
    );
    return page;
  }
}
