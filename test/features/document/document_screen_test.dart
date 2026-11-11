import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/document/presentation/document_screen.dart';
import 'package:cleanleaf/features/document/presentation/extract_text_slot.dart';
import 'package:cleanleaf/features/export/data/export_providers.dart';
import 'package:cleanleaf/features/export/domain/convert_format.dart';
import 'package:cleanleaf/features/library/data/library_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../library/presentation/fakes.dart';

void main() {
  late List<String> sharedPdf;
  late List<String> sharedJpg;
  late List<String> extracted;

  Future<void> pumpDocument(
    WidgetTester tester, {
    String id = 'a',
    bool withExtractText = false,
    ShadThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    sharedPdf = [];
    sharedJpg = [];
    extracted = [];
    final router = GoRouter(
      initialLocation: '/document/$id',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/document/:docId',
          builder: (_, state) =>
              DocumentScreen(documentId: state.pathParameters['docId']!),
        ),
        GoRoute(
          path: '/editor/:pageId',
          builder: (_, state) =>
              Text('editor:${state.pathParameters['pageId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(
            FakeDocumentRepository([fakeDocument('a', 'Receipts')]),
          ),
          pageRepositoryProvider.overrideWithValue(
            FakePageRepository({
              'a': [fakePage('p1', 'a', 0), fakePage('p2', 'a', 1)],
            }),
          ),
          shareDocumentPdfProvider.overrideWithValue(
            (id, {onProgress}) async => sharedPdf.add(id),
          ),
          shareDocumentJpgProvider.overrideWithValue(
            (id) async => sharedJpg.add(id),
          ),
          if (withExtractText)
            extractTextActionProvider.overrideWithValue(
              (context, id) async => extracted.add(id),
            ),
        ],
        child: ShadApp.router(
          theme: theme ?? AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the title, page count and every page', (tester) async {
    await pumpDocument(tester);
    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('2 PAGES · 11 NOV 2026'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
  });

  testWidgets('edit opens the editor on the selected page', (tester) async {
    await pumpDocument(tester);
    await tapAndSettle(tester, find.bySemanticsLabel('Page 2 of 2'));
    await tapAndSettle(tester, find.bySemanticsLabel('Edit'));
    expect(find.text('editor:p2'), findsOneWidget);
  });

  testWidgets('edit defaults to the first page', (tester) async {
    await pumpDocument(tester);
    await tapAndSettle(tester, find.bySemanticsLabel('Edit'));
    expect(find.text('editor:p1'), findsOneWidget);
  });

  testWidgets('convert offers PDF and JPG only', (tester) async {
    await pumpDocument(tester);
    await tapAndSettle(tester, find.bySemanticsLabel('Convert'));
    expect(find.byKey(const ValueKey(ConvertFormat.pdf)), findsOneWidget);
    expect(find.byKey(const ValueKey(ConvertFormat.jpg)), findsOneWidget);
    expect(find.byKey(const ValueKey(ConvertFormat.png)), findsOneWidget);
    expect(find.textContaining('Text'), findsNothing);

    await tapAndSettle(tester, find.byKey(const ValueKey(ConvertFormat.jpg)));
    expect(sharedJpg, ['a']);
  });

  testWidgets('share PDF shares the document', (tester) async {
    await pumpDocument(tester);
    await tapAndSettle(tester, find.bySemanticsLabel('Share PDF'));
    expect(sharedPdf, ['a']);
  });

  testWidgets('rename updates the title', (tester) async {
    await pumpDocument(tester);
    await tapAndSettle(tester, find.bySemanticsLabel('Rename'));
    await tester.enterText(
      find.descendant(
        of: find.byType(ShadDialog),
        matching: find.byType(EditableText),
      ),
      'Tax 2026',
    );
    await tapAndSettle(tester, find.text('Save'));
    expect(find.text('Tax 2026'), findsOneWidget);
  });

  testWidgets('extract text is hidden until OCR provides it', (tester) async {
    await pumpDocument(tester);
    expect(find.bySemanticsLabel('Extract text'), findsNothing);
  });

  testWidgets('extract text runs the provided action', (tester) async {
    await pumpDocument(tester, withExtractText: true);
    await tapAndSettle(tester, find.bySemanticsLabel('Extract text'));
    expect(extracted, ['a']);
  });

  testWidgets('a missing document says so', (tester) async {
    await pumpDocument(tester, id: 'gone');
    expect(find.text('This document no longer exists.'), findsOneWidget);
    expect(find.bySemanticsLabel('Edit'), findsNothing);
  });

  testWidgets('renders in dark theme', (tester) async {
    await pumpDocument(tester, theme: AppTheme.dark);
    expect(find.text('Receipts'), findsOneWidget);
  });
}
