import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/capture/domain/scan_mode.dart';
import 'package:cleanleaf/features/document/presentation/document_screen.dart';
import 'package:cleanleaf/features/export/data/export_providers.dart';
import 'package:cleanleaf/features/export/domain/convert_format.dart';
import 'package:cleanleaf/features/home/presentation/home_screen.dart';
import 'package:cleanleaf/features/library/data/library_providers.dart';
import 'package:cleanleaf/features/library/presentation/document_card.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../library/presentation/fakes.dart';

void main() {
  late FakeDocumentRepository documents;
  late List<String> shared;
  late List<String> sharedJpg;

  Future<void> pumpHome(
    WidgetTester tester, [
    FakeDocumentRepository? repo,
    MemorySettingsStore? settings,
  ]) async {
    tester.view.physicalSize = const Size(400, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    documents = repo ?? FakeDocumentRepository();
    shared = [];
    sharedJpg = [];
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/document/:docId',
          builder: (_, state) =>
              DocumentScreen(documentId: state.pathParameters['docId']!),
        ),
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
          settingsStoreProvider.overrideWithValue(
            settings ?? MemorySettingsStore(),
          ),
          shareDocumentPdfProvider.overrideWithValue(
            (id, {onProgress}) async => shared.add(id),
          ),
          shareDocumentJpgProvider.overrideWithValue(
            (id) async => sharedJpg.add(id),
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
    testWidgets('empty library shows hints and disables edit and convert', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(find.text('Your scans will show up here.'), findsOneWidget);
      expect(find.text('Scan something first'), findsNWidgets(2));

      await tapAndSettle(tester, find.byKey(const ValueKey('tile-edit')));
      await tapAndSettle(tester, find.byKey(const ValueKey('tile-convert')));
      expect(find.byType(ShadSheet), findsNothing);
    });

    testWidgets('tiles are scan, import, edit and convert', (tester) async {
      await pumpHome(tester, twoDocs());
      for (final title in ['Scan', 'Import', 'Edit', 'Convert']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Crop, filters, rotate'), findsOneWidget);
      expect(find.text('PDF, JPG, PNG'), findsOneWidget);
      expect(find.byKey(const ValueKey('tile-files')), findsNothing);
    });

    testWidgets('recent strip lists documents newest first', (tester) async {
      await pumpHome(tester, twoDocs());
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

    testWidgets('quick scan uses the persisted last mode', (tester) async {
      final settings = MemorySettingsStore();
      await settings.write('lastScanMode', 'receipt');
      await pumpHome(tester, null, settings);
      await tapAndSettle(tester, find.byKey(const ValueKey('quick-scan')));
      expect(find.text('capture:receipt'), findsOneWidget);
    });

    testWidgets('icon buttons expose tap actions to TalkBack', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);
      SemanticsData data(String label) =>
          tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
      for (final label in ['Settings', 'About Cleanleaf', 'Files', 'Home']) {
        expect(
          data(label).hasAction(SemanticsAction.tap),
          isTrue,
          reason: label,
        );
      }
      final fab = data('Scan document');
      expect(fab.hasAction(SemanticsAction.tap), isTrue);
      expect(fab.hasAction(SemanticsAction.longPress), isTrue);
      handle.dispose();
    });

    testWidgets('QR code is disabled and close dismisses the sheet', (
      tester,
    ) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('tile-scan')));
      final qr = find.byKey(const ValueKey(ScanMode.qrCode));
      await tester.ensureVisible(qr);
      await tapAndSettle(tester, qr);
      expect(find.text('QR code'), findsOneWidget);

      await tapAndSettle(tester, find.bySemanticsLabel('Close'));
      expect(find.text('QR code'), findsNothing);
      expect(find.textContaining('capture:'), findsNothing);
    });

    Future<void> pickInSheet(WidgetTester tester, String title) => tapAndSettle(
      tester,
      find.descendant(of: find.byType(ShadSheet), matching: find.text(title)),
    );

    testWidgets('convert picks a document and shares its PDF', (tester) async {
      await pumpHome(tester, twoDocs());
      await tapAndSettle(tester, find.byKey(const ValueKey('tile-convert')));
      expect(find.text('Pick a document to convert.'), findsOneWidget);

      await pickInSheet(tester, 'Passport');
      await tapAndSettle(tester, find.byKey(const ValueKey(ConvertFormat.pdf)));
      expect(shared, ['b']);
      expect(sharedJpg, isEmpty);
    });

    testWidgets('convert to JPG shares the page images', (tester) async {
      await pumpHome(tester, twoDocs());
      await tapAndSettle(tester, find.byKey(const ValueKey('tile-convert')));
      await pickInSheet(tester, 'Receipts');
      await tapAndSettle(tester, find.byKey(const ValueKey(ConvertFormat.jpg)));
      expect(sharedJpg, ['a']);
      expect(shared, isEmpty);
    });

    testWidgets('edit picks a document and opens it', (tester) async {
      await pumpHome(tester, twoDocs());
      await tapAndSettle(tester, find.byKey(const ValueKey('tile-edit')));
      expect(find.text('Pick a document to open.'), findsOneWidget);

      await pickInSheet(tester, 'Passport');
      expect(find.byType(DocumentScreen), findsOneWidget);
      expect(find.text('1 PAGE · 11 NOV 2026'), findsOneWidget);
    });

    testWidgets('tapping a recent card opens the document', (tester) async {
      await pumpHome(tester, twoDocs());
      await tapAndSettle(tester, find.text('Receipts'));
      expect(find.text('2 PAGES · 11 NOV 2026'), findsOneWidget);
    });

    testWidgets('deleting in the document view returns home with undo', (
      tester,
    ) async {
      await pumpHome(tester, twoDocs());
      await tapAndSettle(tester, find.text('Receipts'));
      await tapAndSettle(tester, find.bySemanticsLabel('Delete'));
      expect(find.byType(DocumentScreen), findsNothing);
      expect(find.text('Receipts'), findsNothing);
      expect(find.text('Deleted "Receipts"'), findsOneWidget);

      await tapAndSettle(tester, find.text('Undo'));
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Receipts'), findsOneWidget);
      expect(documents.deleted, isEmpty);
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

    testWidgets('tapping a card opens the document', (tester) async {
      await pumpHome(tester, twoDocs());
      await openFiles(tester);
      await tapAndSettle(tester, find.text('Passport'));
      expect(find.byType(DocumentScreen), findsOneWidget);
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
      expect(find.text('Passport'), findsOneWidget);

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
