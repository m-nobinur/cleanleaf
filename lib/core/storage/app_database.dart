import 'package:drift/drift.dart';

import 'app_database.steps.dart';

part 'app_database.g.dart';

// Timestamps are epoch milliseconds; drift's dateTime() keeps only seconds.
@DataClassName('DocumentRow')
class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get folderId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// No UNIQUE on (document_id, page_index): SQLite checks it per row mid-reorder.
@TableIndex(name: 'pages_document_id', columns: {#documentId})
@DataClassName('PageRow')
class Pages extends Table {
  TextColumn get id => text()();
  TextColumn get documentId =>
      text().references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageIndex => integer()();
  TextColumn get originalPath => text()();
  TextColumn get corners => text()();
  TextColumn get detectedCorners => text().nullable()();
  TextColumn get source => text()();
  TextColumn get anchors => text()();
  IntColumn get rotation => integer()();
  TextColumn get filter => text()();
  TextColumn get filterParams => text()();
  TextColumn get renderPath => text().nullable()();
  TextColumn get thumbPath => text().nullable()();
  // Null until the page is queued for OCR (decisions.md D-13a).
  TextColumn get ocrStatus => text().nullable()();
  TextColumn get ocrEngine => text().nullable()();
  TextColumn get ocrLanguage => text().nullable()();
  TextColumn get ocrText => text().nullable()();
  // JSON lines with their words, boxes normalized to the image read.
  TextColumn get ocrLines => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Documents, Pages])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // To change the schema: bump schemaVersion, run
    // `dart run drift_dev make-migrations`, add the step here (D-26).
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        final p = schema.pages;
        for (final column in [
          p.ocrStatus,
          p.ocrEngine,
          p.ocrLanguage,
          p.ocrText,
          p.ocrLines,
        ]) {
          await m.addColumn(p, column);
        }
      },
    ),
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
