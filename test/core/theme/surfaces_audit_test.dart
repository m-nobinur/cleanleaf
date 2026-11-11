// T-036 audit: every non-camera surface in both themes at phone size, with
// real fonts, checked for overflow, AA text contrast, 48 dp targets and
// TalkBack labels. Set AUDIT_SHOTS_DIR to also write a PNG per surface.
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/document/presentation/document_screen.dart';
import 'package:cleanleaf/features/export/data/export_providers.dart';
import 'package:cleanleaf/features/home/presentation/home_screen.dart';
import 'package:cleanleaf/features/library/data/library_providers.dart';
import 'package:cleanleaf/features/library/presentation/document_card.dart';
import 'package:cleanleaf/features/scan_engine/presentation/scan_engine_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../features/library/presentation/fakes.dart';

final _shotsDir = Platform.environment['AUDIT_SHOTS_DIR'];

Future<void> _loadFonts() async {
  final pubCache = '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev';
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  final geist = '$pubCache/shadcn_ui-0.59.0/fonts/Geist[wght].ttf';
  await load('packages/shadcn_ui/Geist', [geist]);
  await load('Geist', [geist]);
  await load('JetBrainsMono', [
    for (final w in ['Regular', 'Medium', 'SemiBold'])
      'assets/fonts/JetBrainsMonoNL-$w.ttf',
  ]);
  await load('packages/lucide_icons_flutter/Lucide', [
    '$pubCache/lucide_icons_flutter-3.1.25/assets/lucide.ttf',
  ]);
}

void main() {
  setUpAll(_loadFonts);

  Future<void> pumpApp(
    WidgetTester tester,
    ShadThemeData theme, {
    String initial = '/',
    bool empty = false,
    bool failShare = false,
  }) async {
    tester.view.physicalSize = const Size(720, 1560);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/document/:docId',
          builder: (_, state) =>
              DocumentScreen(documentId: state.pathParameters['docId']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(
            FakeDocumentRepository(
              empty
                  ? []
                  : [
                      fakeDocument('a', 'Scan 2026-11-12 01.21', minute: 5),
                      fakeDocument('b', 'Lease agreement', minute: 30),
                      fakeDocument('c', 'Receipt — hardware store'),
                    ],
            ),
          ),
          pageRepositoryProvider.overrideWithValue(
            FakePageRepository({
              'a': [fakePage('p1', 'a', 0), fakePage('p2', 'a', 1)],
              'b': [fakePage('p3', 'b', 0)],
              'c': [fakePage('p4', 'c', 0)],
            }),
          ),
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
          googleScannerAvailableProvider.overrideWith((ref) async => true),
          shareDocumentPdfProvider.overrideWithValue(
            (id, {onProgress}) async =>
                failShare ? throw StateError('disk full') : null,
          ),
        ],
        child: ShadApp.router(theme: theme, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> audit(WidgetTester tester, String name) async {
    final dir = _shotsDir;
    if (dir != null) {
      final image = await captureImage(find.byType(ShadApp).evaluate().single);
      await tester.runAsync(() async {
        final png = await image.toByteData(format: ImageByteFormat.png);
        File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
    expect(tester.takeException(), isNull, reason: name);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  }

  final ellipsis = find
      .descendant(
        of: find.byType(DocumentCard),
        matching: find.byIcon(LucideIcons.ellipsis),
      )
      .first;

  for (final (mode, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    group(mode, () {
      testWidgets('home', (tester) async {
        await pumpApp(tester, theme);
        await audit(tester, '${mode}_home');
      });

      testWidgets('files grid and list', (tester) async {
        await pumpApp(tester, theme);
        await tap(tester, find.bySemanticsLabel('Files'));
        await audit(tester, '${mode}_files_grid');
        await tap(tester, find.bySemanticsLabel('Switch to list view'));
        await audit(tester, '${mode}_files_list');
      });

      testWidgets('files empty', (tester) async {
        await pumpApp(tester, theme, empty: true);
        await tap(tester, find.bySemanticsLabel('Files'));
        await audit(tester, '${mode}_files_empty');
      });

      testWidgets('document actions sheet and delete toast', (tester) async {
        await pumpApp(tester, theme);
        await tap(tester, find.bySemanticsLabel('Files'));
        await tap(tester, ellipsis);
        await audit(tester, '${mode}_actions_sheet');
        await tap(tester, find.text('Delete'));
        await audit(tester, '${mode}_toast_undo');
        await tester.pump(const Duration(seconds: 6));
      });

      testWidgets('settings and engine dialog', (tester) async {
        await pumpApp(tester, theme);
        await tap(tester, find.bySemanticsLabel('Settings'));
        await audit(tester, '${mode}_settings_sheet');
        await tap(tester, find.text('Scanner engine'));
        await audit(tester, '${mode}_engine_dialog');
      });

      testWidgets('about sheet', (tester) async {
        await pumpApp(tester, theme);
        await tap(tester, find.bySemanticsLabel('About Cleanleaf'));
        await audit(tester, '${mode}_about_sheet');
      });

      testWidgets('scan mode sheet', (tester) async {
        await pumpApp(tester, theme);
        await tap(tester, find.byKey(const ValueKey('tile-scan')));
        await audit(tester, '${mode}_scan_sheet');
      });

      testWidgets('document picker', (tester) async {
        await pumpApp(tester, theme);
        await tap(tester, find.byKey(const ValueKey('tile-edit')));
        await audit(tester, '${mode}_picker_sheet');
      });

      testWidgets('document view, convert, rename', (tester) async {
        await pumpApp(tester, theme, initial: '/document/a');
        await audit(tester, '${mode}_document');
        await tap(tester, find.bySemanticsLabel('Convert'));
        await audit(tester, '${mode}_convert_sheet');
        await tap(tester, find.bySemanticsLabel('Close'));
        await tap(tester, find.bySemanticsLabel('Rename'));
        // The leaf focus ring is a UI outline (3:1, in app_theme_test) that
        // the text-contrast check would mistake for text.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await audit(tester, '${mode}_rename_dialog');
      });

      testWidgets('missing document', (tester) async {
        await pumpApp(tester, theme, initial: '/document/zz');
        await audit(tester, '${mode}_document_missing');
      });

      testWidgets('error toast', (tester) async {
        await pumpApp(tester, theme, initial: '/document/a', failShare: true);
        await tap(tester, find.bySemanticsLabel('Share PDF'));
        await audit(tester, '${mode}_toast_error');
        await tester.pump(const Duration(seconds: 6));
      });
    });
  }
}
