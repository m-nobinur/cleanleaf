import 'package:cleanleaf/core/storage/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  const versions = GeneratedHelper.versions;
  for (final (i, from) in versions.indexed) {
    for (final to in versions.skip(i + 1)) {
      test('migrates the schema from v$from to v$to', () async {
        final schema = await verifier.schemaAt(from);
        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, to);
        await db.close();
      });
    }
  }

  test('v1 to v2 keeps documents and pages, OCR fields empty', () async {
    const doc = v1.DocumentsData(
      id: 'd',
      title: 'Receipt',
      createdAt: 1,
      updatedAt: 2,
    );
    const page = v1.PagesData(
      id: 'p',
      documentId: 'd',
      pageIndex: 0,
      originalPath: 'docs/d/p/original.jpg',
      corners: '[[0,0],[1,0],[1,1],[0,1]]',
      source: 'camera',
      anchors: '[[],[],[],[]]',
      rotation: 0,
      filter: 'enhancedColor',
      filterParams: '{}',
      renderPath: 'docs/d/p/render.jpg',
    );
    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(oldDb.documents, doc);
        batch.insert(oldDb.pages, page);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.documents).get(), [
          const v2.DocumentsData(
            id: 'd',
            title: 'Receipt',
            createdAt: 1,
            updatedAt: 2,
          ),
        ]);
        expect(await newDb.select(newDb.pages).get(), [
          const v2.PagesData(
            id: 'p',
            documentId: 'd',
            pageIndex: 0,
            originalPath: 'docs/d/p/original.jpg',
            corners: '[[0,0],[1,0],[1,1],[0,1]]',
            source: 'camera',
            anchors: '[[],[],[],[]]',
            rotation: 0,
            filter: 'enhancedColor',
            filterParams: '{}',
            renderPath: 'docs/d/p/render.jpg',
          ),
        ]);
      },
    );
  });
}
