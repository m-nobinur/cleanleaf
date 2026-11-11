import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/capture/domain/scan_mode.dart';
import 'package:cleanleaf/features/export/data/export_providers.dart';
import 'package:cleanleaf/features/home/presentation/home_screen.dart';
import 'package:cleanleaf/features/library/data/library_providers.dart';
import 'package:cleanleaf/features/library/presentation/document_card.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../library/presentation/fakes.dart';

void main() {
  late FakeDocumentRepository documents;
  late List<String> shared;

  Future<void> pumpHome(
    WidgetTester tester, [
    FakeDocumentRepository? repo,
  ]) async {
    tester.view.physicalSize = const Size(400, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    documents = repo ?? FakeDocumentRepository();
    shared = [];
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/capture',
          builder: (_, state) =>
              Text('capture:${state.uri.queryParameters['mode']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
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
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
          shareDocumentPdfProvider.overrideWithValue(
            (id, {onProgress}) async => shared.add(id),
          ),
        ],
        child: ShadApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  FakeDocumentRepository twoDocs() => FakeDocumentRepository([
    fakeDocument('a', 'Receipts', minute: 5),
    fakeDocument('b', 'Passport', minute: 30),
  ]);

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openFiles(WidgetTester tester) =>
      tapAndSettle(tester, find.bySemanticsLabel('Files'));

  Future<void> openMenu(
    WidgetTester tester,
    String title,
    String action,
  ) async {
    await tapAndSettle(
      tester,
      find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(DocumentCard),
        ),
        matching: find.byIcon(LucideIcons.ellipsis),
      ),
    );
    await tapAndSettle(tester, find.text(action));
  }

  group('home', () {
    testWidgets('empty library shows hints and disables export', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(find.text('Your scans will show up here.'), findsOneWidget);
      expect(find.text('0 documents'), findsOneWidget);
      expect(find.text('Scan something first'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const ValueKey('tile-export')));
      expect(find.text('Export PDF'), findsNothing);
    });

    testWidgets('recent strip lists documents newest first', (tester) async {
      await pumpHome(tester, twoDocs());
      expect(find.text('2 documents'), findsOneWidget);
      expect(find.text('2 pages · 11 Nov 2026'), findsOneWidget);
      expect(find.text('1 page · 11 Nov 2026'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Passport')).dx,
        lessThan(tester.getTopLeft(find.text('Receipts')).dx),
      );
    });

    testWidgets('search filters documents by title', (tester) async {
      await pumpHome(tester, twoDocs());
      await tester.enterText(find.byType(EditableText), 'PASS');
      await tester.pumpAndSettle();
      expect(find.text('RESULTS'), findsOneWidget);
      expect(find.text('Passport'), findsOneWidget);
      expect(find.text('Receipts'), findsNothing);

      await tester.enterText(find.byType(EditableText), 'tax');
      await tester.pumpAndSettle();
      expect(find.text('No documents match "tax".'), findsOneWidget);
    });

    testWidgets('scan tile opens the mode sheet and routes with the mode', (
      tester,
    ) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('tile-scan')));
      expect(find.text('ID card'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const ValueKey(ScanMode.receipt)));
      expect(find.text('capture:receipt'), findsOneWidget);
    });

    testWidgets('quick scan reuses the last chosen mode', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('quick-scan')));
      expect(find.text('capture:document'), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey('quick-scan')));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byKey(const ValueKey(ScanMode.idCard)));
      expect(find.text('capture:idCard'), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byKey(const ValueKey('quick-scan')));
      expect(find.text('capture:idCard'), findsOneWidget);
    });

    testWidgets('book is disabled and close dismisses the sheet', (
      tester,
    ) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('tile-scan')));
      await tapAndSettle(tester, find.byKey(const ValueKey(ScanMode.book)));
      expect(find.text('Book'), findsOneWidget);

      await tapAndSettle(tester, find.bySemanticsLabel('Close'));
      expect(find.text('Book'), findsNothing);
      expect(find.textContaining('capture:'), findsNothing);
    });

    testWidgets('export picks a document and shares its PDF', (tester) async {
      await pumpHome(tester, twoDocs());
      await tapAndSettle(tester, find.byKey(const ValueKey('tile-export')));
      expect(find.text('Export PDF'), findsOneWidget);

      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(ShadSheet),
          matching: find.text('Passport'),
        ),
      );
      expect(shared, ['b']);
    });

    testWidgets('files tile switches to the files tab', (tester) async {
      await pumpHome(tester, twoDocs());
      await tapAndSettle(tester, find.byKey(const ValueKey('tile-files')));
      expect(find.text('2 DOCUMENTS'), findsOneWidget);
    });

    testWidgets('opens settings with the row list', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.bySemanticsLabel('Settings'));
      expect(find.text('Private by design'), findsOneWidget);
    });

    testWidgets('help opens the about sheet', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.bySemanticsLabel('About Cleanleaf'));
      expect(find.text('Open source licenses'), findsOneWidget);
    });
  });

  group('files tab', () {
    testWidgets('shows the empty state', (tester) async {
      await pumpHome(tester);
      await openFiles(tester);
      expect(find.text('No documents yet'), findsOneWidget);
    });

    testWidgets('toggles to list layout', (tester) async {
      await pumpHome(tester, twoDocs());
      await openFiles(tester);
      await tapAndSettle(tester, find.byIcon(LucideIcons.list));
      expect(find.text('Receipts'), findsOneWidget);
      expect(find.byIcon(LucideIcons.layoutGrid), findsOneWidget);
    });

    testWidgets('renames a document', (tester) async {
      await pumpHome(tester, twoDocs());
      await openFiles(tester);
      await openMenu(tester, 'Receipts', 'Rename');
      await tester.enterText(
        find.descendant(
          of: find.byType(ShadDialog),
          matching: find.byType(EditableText),
        ),
        'Tax 2026',
      );
      await tapAndSettle(tester, find.text('Save'));
      expect(find.text('Tax 2026'), findsOneWidget);
      expect(find.text('Receipts'), findsNothing);
    });

    testWidgets('shares a PDF from the menu', (tester) async {
      await pumpHome(tester, twoDocs());
      await openFiles(tester);
      await openMenu(tester, 'Receipts', 'Share PDF');
      expect(shared, ['a']);
    });

    testWidgets('delete hides the document and undo restores it', (
      tester,
    ) async {
      await pumpHome(tester, twoDocs());
      await openFiles(tester);
      await openMenu(tester, 'Receipts', 'Delete');
      expect(find.text('Receipts'), findsNothing);
      expect(documents.deleted, isEmpty);

      await tapAndSettle(tester, find.text('Undo'));
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Receipts'), findsOneWidget);
      expect(documents.deleted, isEmpty);
    });

    testWidgets('undo still works after switching to home', (tester) async {
      await pumpHome(tester, twoDocs());
      await openFiles(tester);
      await openMenu(tester, 'Receipts', 'Delete');
      await tapAndSettle(tester, find.bySemanticsLabel('Home'));
      expect(find.text('Receipts'), findsNothing);
      expect(find.text('1 document'), findsOneWidget);

      await tapAndSettle(tester, find.text('Undo'));
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Receipts'), findsOneWidget);
      expect(documents.deleted, isEmpty);
    });

    testWidgets('delete is committed once the undo window ends', (
      tester,
    ) async {
      await pumpHome(tester, twoDocs());
      await openFiles(tester);
      await openMenu(tester, 'Receipts', 'Delete');
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(documents.deleted, ['a']);
      expect(find.text('Receipts'), findsNothing);
    });
  });
}
