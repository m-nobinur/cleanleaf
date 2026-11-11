import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/library/data/library_providers.dart';
import 'package:cleanleaf/features/library/presentation/document_card.dart';
import 'package:cleanleaf/features/library/presentation/library_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'fakes.dart';

void main() {
  late FakeDocumentRepository documents;

  Future<void> pumpLibrary(
    WidgetTester tester, [
    FakeDocumentRepository? repo,
  ]) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    documents = repo ?? FakeDocumentRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(documents),
          pageRepositoryProvider.overrideWithValue(
            FakePageRepository({
              'a': [fakePage('p1', 'a', 0), fakePage('p2', 'a', 1)],
              'b': [fakePage('p3', 'b', 0)],
            }),
          ),
        ],
        child: ShadApp(theme: AppTheme.light, home: const LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  FakeDocumentRepository twoDocs() => FakeDocumentRepository([
    fakeDocument('a', 'Receipts', minute: 5),
    fakeDocument('b', 'Passport', minute: 30),
  ]);

  Future<void> openMenu(
    WidgetTester tester,
    String title,
    String action,
  ) async {
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(DocumentCard),
        ),
        matching: find.byIcon(LucideIcons.ellipsis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state with a hint', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('No documents yet'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });

  testWidgets('lists documents newest first with page count', (tester) async {
    await pumpLibrary(tester, twoDocs());
    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('2 pages · 11 Nov 2026'), findsOneWidget);
    expect(find.text('1 page · 11 Nov 2026'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Passport')).dx,
      lessThan(tester.getTopLeft(find.text('Receipts')).dx),
    );
  });

  testWidgets('toggles to list layout', (tester) async {
    await pumpLibrary(tester, twoDocs());
    await tester.tap(find.byIcon(LucideIcons.list));
    await tester.pumpAndSettle();
    expect(find.text('Receipts'), findsOneWidget);
    expect(find.byIcon(LucideIcons.layoutGrid), findsOneWidget);
  });

  testWidgets('renames a document', (tester) async {
    await pumpLibrary(tester, twoDocs());
    await openMenu(tester, 'Receipts', 'Rename');
    await tester.enterText(find.byType(EditableText), 'Tax 2026');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Tax 2026'), findsOneWidget);
    expect(find.text('Receipts'), findsNothing);
  });

  testWidgets('delete hides the document and undo restores it', (tester) async {
    await pumpLibrary(tester, twoDocs());
    await openMenu(tester, 'Receipts', 'Delete');
    expect(find.text('Receipts'), findsNothing);
    expect(documents.deleted, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Receipts'), findsOneWidget);
    expect(documents.deleted, isEmpty);
  });

  testWidgets('delete is committed once the undo window ends', (tester) async {
    await pumpLibrary(tester, twoDocs());
    await openMenu(tester, 'Receipts', 'Delete');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(documents.deleted, ['a']);
    expect(find.text('Receipts'), findsNothing);
  });

  testWidgets('opens settings with the row list', (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.byIcon(LucideIcons.settings));
    await tester.pumpAndSettle();
    expect(find.text('Private by design'), findsOneWidget);
  });
}
