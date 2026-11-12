import 'dart:async';
import 'dart:developer';

import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/file_store.dart';
import '../../library/domain/document_page.dart';
import '../domain/ocr_engine.dart';
import '../domain/ocr_language.dart';
import 'ocr_row_mapper.dart';

/// Reads pages whose OCR status is pending, one at a time, while the app runs
/// (decisions.md D-13a). The status column is the queue, so a new render or a
/// deleted page needs no call here.
class OcrQueue {
  OcrQueue(this._db, this._files, this._engine);

  final AppDatabase _db;
  final FileStore _files;
  final OcrEngine _engine;
  final _urgent = <String>{};
  StreamSubscription<void>? _changes;
  bool _busy = false;
  bool _again = false;

  Future<void> start() async {
    // A page left running was interrupted when the process died.
    await (_db.update(_db.pages)
          ..where((t) => t.ocrStatus.equals(OcrStatus.running.name)))
        .write(PagesCompanion(ocrStatus: Value(OcrStatus.pending.name)));
    _changes = _db
        .tableUpdates(TableUpdateQuery.onTable(_db.pages))
        .listen((_) => _pump());
    unawaited(_pump());
  }

  Future<void> stop() async => _changes?.cancel();

  /// Queues [pageId] in [language] ahead of background work.
  Future<void> request(String pageId, OcrLanguage language) async {
    await (_db.update(_db.pages)..where((t) => t.id.equals(pageId))).write(
      PagesCompanion(
        ocrStatus: Value(OcrStatus.pending.name),
        ocrLanguage: Value(language.name),
      ),
    );
    prioritize(pageId);
  }

  void prioritize(String pageId) {
    _urgent.add(pageId);
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    var read = false;
    try {
      do {
        _again = false;
        for (var row = await _next(); row != null; row = await _next()) {
          await _read(row);
          read = true;
        }
      } while (_again);
    } finally {
      _busy = false;
    }
    // An idle engine holds hundreds of MB (decisions.md D-64).
    if (read) await _engine.release();
  }

  Future<PageRow?> _next() async {
    final pending = {
      for (final row in await (_db.select(
        _db.pages,
      )..where((t) => t.ocrStatus.equals(OcrStatus.pending.name))).get())
        row.id: row,
    };
    _urgent.retainWhere(pending.containsKey);
    final row = _urgent.isEmpty
        ? pending.values.firstOrNull
        : pending[_urgent.first];
    _urgent.remove(row?.id);
    return row;
  }

  Future<void> _read(PageRow row) async {
    final language = ocrLanguageOf(row);
    final claimed = await _moveFrom(
      OcrStatus.pending,
      row.id,
    ).write(PagesCompanion(ocrStatus: Value(OcrStatus.running.name)));
    if (claimed == 0) return;
    // Deleted, re-rendered or re-requested pages stop being running.
    final stale = (_db.select(_db.pages)..where((t) => t.id.equals(row.id)))
        .watchSingleOrNull()
        .where((r) => r?.ocrStatus != OcrStatus.running.name)
        .listen((_) => _engine.cancel());
    try {
      final image = await _files.resolve(row.renderPath ?? row.originalPath);
      final result = await _engine.recognize(image.path, language);
      if (result == null) return;
      await _moveFrom(OcrStatus.running, row.id).write(
        PagesCompanion(
          ocrStatus: Value(OcrStatus.done.name),
          ocrEngine: Value(result.engine),
          ocrLanguage: Value(result.language.name),
          ocrText: Value(result.text),
          ocrLines: Value(encodeOcrLines(result.lines)),
        ),
      );
    } catch (e, stack) {
      log('OCR failed for ${row.id}', error: e, stackTrace: stack);
      await _moveFrom(
        OcrStatus.running,
        row.id,
      ).write(PagesCompanion(ocrStatus: Value(OcrStatus.failed.name)));
    } finally {
      await stale.cancel();
    }
  }

  // Writes only while the page is still in [status], so stale results drop.
  UpdateStatement<$PagesTable, PageRow> _moveFrom(
    OcrStatus status,
    String pageId,
  ) =>
      _db.update(_db.pages)
        ..where((t) => t.id.equals(pageId) & t.ocrStatus.equals(status.name));
}
