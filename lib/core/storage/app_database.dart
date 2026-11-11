import 'package:drift/drift.dart';

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
  TextColumn get anchors => text()();
  IntColumn get rotation => integer()();
  TextColumn get filter => text()();
  TextColumn get filterParams => text()();
  TextColumn get renderPath => text().nullable()();
  TextColumn get thumbPath => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Documents, Pages])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // No onUpgrade yet: drift's default throws on a version bump without steps.
    // Add them with `dart run drift_dev make-migrations` when bumping schemaVersion.
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
