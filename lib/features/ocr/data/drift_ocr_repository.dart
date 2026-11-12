import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../../library/data/drift_document_repository.dart';
import '../../library/domain/document.dart';
import '../../library/domain/document_page.dart';
import '../domain/ocr_language.dart';
import '../domain/ocr_repository.dart';
import '../domain/ocr_result.dart';
import 'ocr_queue.dart';
import 'ocr_row_mapper.dart';

class DriftOcrRepository implements OcrRepository {
  DriftOcrRepository(this._db, this._queue);

  final AppDatabase _db;
  final OcrQueue _queue;

  @override
  Stream<OcrStatus?> watchStatus(String pageId) =>
      _byId(pageId)
          .map((r) => r.ocrStatus == null ? null : _status(r))
          .watchSingleOrNull();

  @override
  Stream<Set<String>> watchReadingDocumentIds() {
    final p = _db.pages;
    return (_db.selectOnly(p, distinct: true)
          ..addColumns([p.documentId])
          ..where(
            p.ocrStatus.isIn([OcrStatus.pending.name, OcrStatus.running.name]),
          ))
        .map((r) => r.read(p.documentId)!)
        .watch()
        .map((ids) => ids.toSet());
  }

  @override
  Future<OcrResult> extractText(String pageId, OcrLanguage? language) async {
    final row = await _byId(pageId).getSingle();
    final status = row.ocrStatus == null ? null : _status(row);
    if ((language != null && ocrLanguageOf(row) != language) ||
        status == null ||
        status == OcrStatus.failed) {
      await _queue.request(pageId, language ?? OcrLanguage.auto);
    } else if (status != OcrStatus.done) {
      _queue.prioritize(pageId);
    }
    final read = await _byId(pageId).watchSingleOrNull().firstWhere(
      (r) =>
          r == null ||
          r.ocrStatus == OcrStatus.done.name ||
          r.ocrStatus == OcrStatus.failed.name,
    );
    if (read == null || read.ocrStatus != OcrStatus.done.name) {
      throw OcrFailed(pageId);
    }
    return ocrResultOf(read);
  }

  @override
  Stream<List<Document>> watchSearch(String query) {
    final select = _db.select(_db.documents)
      ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]);
    for (final term in query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty)) {
      final pattern =
          '%${term.replaceAllMapped(_likeSpecial, (m) => '\\${m[0]}')}%';
      select.where(
        (d) =>
            d.title.like(pattern, escapeChar: r'\') |
            existsQuery(
              _db.select(_db.pages)..where(
                (p) =>
                    p.documentId.equalsExp(d.id) &
                    p.ocrText.like(pattern, escapeChar: r'\'),
              ),
            ),
      );
    }
    return select.watch().map((rows) => rows.map(documentFromRow).toList());
  }

  SimpleSelectStatement<$PagesTable, PageRow> _byId(String pageId) =>
      _db.select(_db.pages)..where((t) => t.id.equals(pageId));
}

final _likeSpecial = RegExp(r'[\\%_]');

OcrStatus _status(PageRow r) => OcrStatus.values.byName(r.ocrStatus!);
