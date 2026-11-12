// T-036 audit: every non-camera surface in both themes at phone size, with
// real fonts, checked for overflow, AA text contrast, 48 dp targets and
// TalkBack labels. Set AUDIT_SHOTS_DIR to also write a PNG per surface.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/capture/data/capture_providers.dart';
import 'package:cleanleaf/features/capture/domain/document_camera.dart';
import 'package:cleanleaf/features/capture/domain/scan_mode.dart';
import 'package:cleanleaf/features/capture/presentation/capture_screen.dart';
import 'package:cleanleaf/features/capture/presentation/code_result_sheet.dart';
import 'package:cleanleaf/features/document/presentation/document_screen.dart';
import 'package:cleanleaf/features/export/data/export_providers.dart';
import 'package:cleanleaf/features/home/presentation/home_screen.dart';
import 'package:cleanleaf/features/library/data/library_providers.dart';
import 'package:cleanleaf/features/library/presentation/document_card.dart';
import 'package:cleanleaf/features/ocr/data/ocr_providers.dart';
import 'package:cleanleaf/features/scan_engine/presentation/scan_engine_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../features/capture/presentation/fake_camera.dart';
import '../../features/library/presentation/fakes.dart';

final _shotsDir = Platform.environment['AUDIT_SHOTS_DIR'];

// Package roots come from the resolved package config, so version bumps and
// other machines keep working.
String _packageRoot(String name) {
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final package = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['name'] == name);
  return Uri.parse('${File('.dart_tool/package_config.json').absolute.uri}')
      .resolve(package['rootUri'] as String)
      .toFilePath();
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  final geist = '${_packageRoot('shadcn_ui')}/fonts/Geist[wght].ttf';
  await load('packages/shadcn_ui/Geist', [geist]);
  await load('Geist', [geist]);
  await load('JetBrainsMono', [
    for (final w in ['Regular', 'Medium', 'SemiBold'])
      'assets/fonts/JetBrainsMonoNL-$w.ttf',
  ]);
  await load('packages/lucide_icons_flutter/Lucide', [
    '${_packageRoot('lucide_icons_flutter')}/assets/lucide.ttf',
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
    int extra = 0,
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
                      for (var i = 0; i < extra; i++)
                        fakeDocument('x$i', 'Extra $i', minute: 1),
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
          ocrRepositoryProvider.overrideWithValue(FakeOcrRepository()),
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

  Future<void> audit(
    WidgetTester tester,
    String name, {
    bool labels = true,
  }) async {
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
    if (labels) {
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    }
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
        // With rows behind the floating bar, the last card scrolls fully
        // clear of it (bottom padding = bar height + gap).
        await pumpApp(tester, theme, extra: 4);
        await tap(tester, find.bySemanticsLabel('Files'));
        final lastAtRest = find.ancestor(
          of: find.text('Receipt — hardware store'),
          matching: find.byType(DocumentCard),
        );
        final barTop = tester.getTopLeft(find.bySemanticsLabel('Home')).dy;
        expect(
          tester.getBottomLeft(lastAtRest).dy,
          greaterThan(barTop),
          reason: 'at rest the last card sits behind the bar',
        );
        await tester.drag(find.byType(GridView), const Offset(0, -2000));
        await tester.pumpAndSettle();
        final last = find.ancestor(
          of: find.text('Receipt — hardware store'),
          matching: find.byType(DocumentCard),
        );
        expect(tester.getBottomLeft(last).dy, lessThan(barTop));
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
        // Closing the dialog returns to the settings sheet.
        await tap(tester, find.bySemanticsLabel('Close').last);
        expect(find.text('Scanner engine'), findsOneWidget);
        expect(find.text('About & licenses'), findsOneWidget);
        expect(
          find.text('On this device, fully private. Default.'),
          findsNothing,
        );
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

      testWidgets('rename dialog with the keyboard up', (tester) async {
        await pumpApp(tester, theme, initial: '/document/a');
        tester.view.viewInsets = const FakeViewPadding(bottom: 600);
        await tap(tester, find.bySemanticsLabel('Rename'));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await audit(tester, '${mode}_rename_keyboard');
        final keyboardTop = 780 - 600 / tester.view.devicePixelRatio;
        expect(
          tester.getBottomLeft(find.text('Cancel')).dy,
          lessThanOrEqualTo(keyboardTop),
        );
      });

      testWidgets('code result sheet', (tester) async {
        await pumpApp(tester, theme);
        final context = tester.element(find.byType(HomeScreen));
        unawaited(
          showCodeResult(context, (
            format: 'QR Code',
            text: 'https://example.org/menu?table=12',
          ), openLink: (_) async => true),
        );
        await tester.pumpAndSettle();
        await audit(tester, '${mode}_code_result');
      });

      for (final scanMode in [ScanMode.document, ScanMode.receipt]) {
        testWidgets('live camera ${scanMode.name}', (tester) async {
          tester.view.physicalSize = const Size(720, 1560);
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                documentCameraProvider.overrideWithValue(FakeCamera()),
                settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
              ],
              child: ShadApp(
                theme: theme,
                home: CaptureScreen(mode: scanMode),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // The tap-to-focus preview has no TalkBack label yet; reported in
          // T-036.result for the capture owner (this ticket avoids capture/).
          await audit(tester, '${mode}_camera_${scanMode.name}', labels: false);
        });
      }

      testWidgets('picker with a long library scrolls lazily', (tester) async {
        await pumpApp(tester, theme, extra: 12);
        await tap(tester, find.byKey(const ValueKey('tile-edit')));
        expect(tester.takeException(), isNull);
        final lastRow = find.text('Receipt — hardware store');
        await tester.scrollUntilVisible(
          lastRow,
          200,
          scrollable: find
              .descendant(
                of: find.byType(ShadSheet),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        await tap(tester, lastRow);
        expect(find.text('Receipt — hardware store'), findsWidgets);
        expect(find.bySemanticsLabel('Share PDF'), findsOneWidget);
      });

      testWidgets('camera permission notice', (tester) async {
        tester.view.physicalSize = const Size(720, 1560);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              documentCameraProvider.overrideWithValue(
                FakeCamera()..permission = CameraPermission.permanentlyDenied,
              ),
              settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
            ],
            child: ShadApp(
              theme: theme,
              home: const CaptureScreen(mode: ScanMode.document),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await audit(tester, '${mode}_camera_permission');
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
