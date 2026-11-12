import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/library/domain/document.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/ocr/data/ocr_providers.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_language.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_repository.dart';
import 'package:cleanleaf/features/ocr/domain/ocr_result.dart';
import 'package:cleanleaf/features/ocr/presentation/extract_text_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Pages read in their stored language unless asked for another; ids in
/// [failing] throw.
class _FakeOcr implements OcrRepository {
  _FakeOcr(this.stored, {this.failing = const {}});

  final Map<String, (String, OcrLanguage)> stored;
  final Set<String> failing;
  final calls = <(String, OcrLanguage?)>[];

  @override
  Future<OcrResult> extractText(String pageId, OcrLanguage? language) async {
    calls.add((pageId, language));
    if (failing.contains(pageId)) throw OcrFailed(pageId);
    final (text, storedIn) = stored[pageId]!;
    final readIn = language ?? storedIn;
    return OcrResult(
      readIn == storedIn ? text : '$text (${readIn.name})',
      lines: const [],
      engine: 'fake',
      language: readIn,
    );
  }

  @override
  Stream<OcrStatus?> watchStatus(String pageId) => const Stream.empty();

  @override
  Stream<Set<String>> watchReadingDocumentIds() => const Stream.empty();

  @override
  Stream<List<Document>> watchSearch(String query) => const Stream.empty();
}

void main() {
  Future<void> pumpSheet(
    WidgetTester tester,
    _FakeOcr ocr, {
    List<String> pageIds = const ['p1'],
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ocrRepositoryProvider.overrideWithValue(ocr)],
        child: ShadApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => ShadButton(
              onPressed: () => showExtractTextSheet(
                context,
                title: 'Receipts',
                pageIds: pageIds,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the stored text in its own language', (tester) async {
    final ocr = _FakeOcr({'p1': ('আমার সোনার বাংলা', OcrLanguage.bangla)});
    await pumpSheet(tester, ocr);

    expect(find.text('Extract text'), findsOneWidget);
    expect(find.text('আমার সোনার বাংলা'), findsOneWidget);
    expect(ocr.calls, [('p1', null)], reason: 'no forced re-read');
    expect(
      tester.getSemantics(find.text('বাংলা')),
      isSemantics(isSelected: true),
    );
  });

  testWidgets('another language reads the page again', (tester) async {
    final ocr = _FakeOcr({'p1': ('Invoice', OcrLanguage.auto)});
    await pumpSheet(tester, ocr);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(ocr.calls.last, ('p1', OcrLanguage.english));
    expect(find.text('Invoice (english)'), findsOneWidget);
  });

  testWidgets('joins pages and says which could not be read', (tester) async {
    final ocr = _FakeOcr(
      {'p1': ('First', OcrLanguage.auto), 'p3': ('Third', OcrLanguage.auto)},
      failing: {'p2'},
    );
    await pumpSheet(tester, ocr, pageIds: ['p1', 'p2', 'p3']);

    expect(find.text('First\n\nThird'), findsOneWidget);
    expect(find.text('1 page could not be read.'), findsOneWidget);
  });

  testWidgets('a failed read offers to try again', (tester) async {
    final ocr = _FakeOcr({}, failing: {'p1'});
    await pumpSheet(tester, ocr);

    expect(find.text("Couldn't read the text."), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(ocr.calls, [('p1', null), ('p1', OcrLanguage.auto)]);
  });

  testWidgets('copy puts the text on the clipboard', (tester) async {
    final ocr = _FakeOcr({'p1': ('Invoice #42', OcrLanguage.auto)});
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await pumpSheet(tester, ocr);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'Invoice #42');
    expect(find.text('Copied'), findsOneWidget);
  });
}
