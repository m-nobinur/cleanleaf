import 'dart:io';
import 'dart:typed_data';

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/core/storage/file_store.dart';
import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/editor/presentation/editor_providers.dart';
import 'package:cleanleaf/features/enhance/data/enhance_providers.dart';
import 'package:cleanleaf/features/enhance/domain/page_renderer.dart';
import 'package:cleanleaf/features/enhance/presentation/enhance_screen.dart';
import 'package:cleanleaf/features/library/data/library_providers.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/library/domain/page_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:shadcn_ui/shadcn_ui.dart';

typedef RenderCall = ({PageFilter filter, int rotation, int maxLongSide});

class FakeRenderer implements PageRenderer {
  final calls = <RenderCall>[];
  final params = <Map<String, double>>[];
  final _png = Uint8List.fromList(
    img.encodePng(img.Image(width: 4, height: 3)),
  );

  @override
  Future<Uint8List> render(
    String originalPath,
    Quad quad,
    int rotation,
    PageFilter filter,
    Map<String, double> params, {
    int maxLongSide = 0,
    bool png = false,
  }) async {
    calls.add((filter: filter, rotation: rotation, maxLongSide: maxLongSide));
    this.params.add(params);
    return _png;
  }

  @override
  Future<Uint8List> thumbnail(
    Uint8List image, {
    int maxSide = thumbnailMaxSide,
  }) async => image;
}

class FakePageRepository extends Fake implements PageRepository {
  FakePageRepository(this.page);

  DocumentPage page;
  DocumentPage? edited;
  Uint8List? savedRender;

  @override
  Future<DocumentPage?> get(String pageId) async =>
      pageId == page.id ? page : null;

  @override
  Future<void> saveRender(
    String pageId, {
    required Stream<List<int>> render,
    required Stream<List<int>> thumb,
  }) async {
    savedRender = Uint8List.fromList([
      for (final chunk in await render.toList()) ...chunk,
    ]);
    await thumb.drain<void>();
  }

  @override
  Future<void> updateEdits(DocumentPage page) async => edited = page;
}

Future<({FakeRenderer renderer, FakePageRepository repo})> pumpEnhance(
  WidgetTester tester, {
  bool afterEditor = false,
  Map<String, double> filterParams = const {},
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final renderer = FakeRenderer();
  final repo = FakePageRepository(
    DocumentPage(
      'p1',
      documentId: 'd1',
      index: 0,
      originalPath: 'docs/d1/p1/original.jpg',
      corners: fullFrame,
      filterParams: filterParams,
    ),
  );
  final router = GoRouter(
    initialLocation: afterEditor ? '/' : '/enhance/p1',
    routes: [
      GoRoute(
        path: '/enhance/:pageId',
        builder: (_, state) =>
            EnhanceScreen(pageId: state.pathParameters['pageId']!),
      ),
      GoRoute(
        path: '/editor/:pageId',
        builder: (context, _) => TextButton(
          onPressed: () => context.go('/enhance/p1'),
          child: const Text('Editor stub'),
        ),
      ),
      GoRoute(
        path: '/',
        builder: (context, _) => afterEditor
            ? TextButton(
                onPressed: () => context.push('/enhance/p1'),
                child: const Text('Open'),
              )
            : const Text('Library stub'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pageRepositoryProvider.overrideWithValue(repo),
        pageRendererProvider.overrideWithValue(renderer),
        fileStoreProvider.overrideWithValue(
          FileStore(() async => Directory.systemTemp),
        ),
      ],
      child: ShadApp.router(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (afterEditor) {
    // The editor stays mounted under enhance, holding its pre-crop page.
    final container = ProviderScope.containerOf(
      tester.element(find.text('Open')),
    );
    final keepAlive = container.listen(editorPageProvider('p1'), (_, _) {});
    addTearDown(keepAlive.close);
    await container.read(editorPageProvider('p1').future);
    repo.page = repo.page.copyWith(
      rotation: 90,
      corners: (
        topLeft: (x: 0.2, y: 0.2),
        topRight: (x: 0.8, y: 0.2),
        bottomRight: (x: 0.8, y: 0.8),
        bottomLeft: (x: 0.2, y: 0.8),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
  return (renderer: renderer, repo: repo);
}

void main() {
  testWidgets('previews Enhanced first; a chip switches the preview filter', (
    tester,
  ) async {
    final (:renderer, repo: _) = await pumpEnhance(tester);

    bool previewed(PageFilter f) =>
        renderer.calls.any((c) => c.filter == f && c.maxLongSide > 400);
    expect(previewed(PageFilter.enhancedColor), isTrue);
    expect(previewed(PageFilter.grayscale), isFalse);

    await tester.tap(find.text('Grayscale'));
    await tester.pumpAndSettle();

    expect(previewed(PageFilter.grayscale), isTrue);
  });

  testWidgets('holding the page shows the original look', (tester) async {
    final (:renderer, repo: _) = await pumpEnhance(tester);
    bool previewedOriginal() => renderer.calls.any(
      (c) => c.filter == PageFilter.original && c.maxLongSide > 400,
    );
    expect(previewedOriginal(), isFalse);

    final hold = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('Page preview')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(previewedOriginal(), isTrue);
    expect(find.text('Original'), findsWidgets);
    await hold.up();
    await tester.pumpAndSettle();
  });

  testWidgets('Save stores the chosen filter and rotation with a full render', (
    tester,
  ) async {
    final (:renderer, :repo) = await pumpEnhance(tester);

    await tester.tap(find.text('B&W'));
    await tester.tap(find.byIcon(LucideIcons.rotateCw));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ShadButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.edited!.filter, PageFilter.blackWhite);
    expect(repo.edited!.rotation, 90);
    expect(repo.savedRender, isNotEmpty);
    expect(renderer.calls.last, (
      filter: PageFilter.blackWhite,
      rotation: 90,
      maxLongSide: 0,
    ));
    expect(find.text('Library stub'), findsOneWidget);
  });

  testWidgets('opens on the page as saved by the editor, not its cached copy', (
    tester,
  ) async {
    final (:renderer, :repo) = await pumpEnhance(tester, afterEditor: true);

    expect(renderer.calls.first.rotation, 90);
    await tester.tap(find.widgetWithText(ShadButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.edited!.rotation, 90);
  });

  for (final (mode, theme) in [
    (ThemeMode.light, AppTheme.light),
    (ThemeMode.dark, AppTheme.dark),
  ]) {
    testWidgets('follows the app theme: ${mode.name}', (tester) async {
      await pumpEnhance(tester, themeMode: mode);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, theme.colorScheme.background);
    });
  }

  group('Adjust', () {
    Future<void> openAdjust(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Adjust'));
      await tester.pumpAndSettle();
    }

    Future<void> dragSlider(WidgetTester tester, double dx) async {
      final slider = find.byType(ShadSlider);
      final gesture = await tester.startGesture(tester.getCenter(slider));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(Offset(dx / 4, 0));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('dragging previews small, releasing renders full', (
      tester,
    ) async {
      final (:renderer, repo: _) = await pumpEnhance(tester);
      await openAdjust(tester);
      final before = renderer.calls.length;

      await dragSlider(tester, 60);

      final calls = renderer.calls.sublist(before);
      final params = renderer.params.sublist(before);
      expect(calls.first.maxLongSide, 800);
      expect(params.first['brightness'], greaterThan(0));
      expect(calls.last.maxLongSide, 1600);
      final brightness = params.last['brightness']!;
      expect(brightness, greaterThan(0));
      expect(find.text('+${(brightness * 100).round()}'), findsOneWidget);
    });

    testWidgets('reset clears one slider, Reset clears all', (tester) async {
      final (:renderer, repo: _) = await pumpEnhance(tester);
      await openAdjust(tester);
      await dragSlider(tester, 60);
      await tester.tap(find.bySemanticsLabel('Contrast'));
      await tester.pumpAndSettle();
      await dragSlider(tester, -60);
      expect(
        renderer.params.last.keys,
        containsAll(['brightness', 'contrast']),
      );

      await tester.tap(find.byIcon(LucideIcons.rotateCcw));
      await tester.pumpAndSettle();
      expect(renderer.params.last.keys, ['brightness']);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(renderer.params.last, isEmpty);
      expect(find.text('Reset'), findsNothing);
    });

    testWidgets('Save stores the adjustments beside the aspect ratio', (
      tester,
    ) async {
      final (:renderer, :repo) = await pumpEnhance(
        tester,
        filterParams: {aspectRatioParam: 1.5},
      );
      await openAdjust(tester);
      await tester.tap(find.bySemanticsLabel('Straighten'));
      await tester.pumpAndSettle();
      await dragSlider(tester, 40);
      await tester.tap(find.widgetWithText(ShadButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = repo.edited!.filterParams;
      expect(saved[aspectRatioParam], 1.5);
      expect(saved['straighten'], greaterThan(0));
      expect(saved.keys, unorderedEquals([aspectRatioParam, 'straighten']));
      expect(renderer.params.last, saved);
      expect(renderer.calls.last.maxLongSide, 0);
    });

    testWidgets('Perspective opens the editor and keeps unsaved edits', (
      tester,
    ) async {
      await pumpEnhance(tester);
      await tester.tap(find.text('B&W'));
      await openAdjust(tester);
      await tester.tap(find.bySemanticsLabel('Straighten'));
      await tester.pumpAndSettle();
      await dragSlider(tester, 40);
      final readout = find.textContaining('°');
      final shown = tester.widget<Text>(readout).data;

      await tester.tap(find.bySemanticsLabel(RegExp('^Perspective')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editor stub'));
      await tester.pumpAndSettle();
      await openAdjust(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^Straighten')));
      await tester.pumpAndSettle();

      expect(find.text(shown!), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('^Brightness')));
      await tester.pumpAndSettle();
      // B&W survived the trip too: tone has no effect on it.
      expect(find.text('No effect on B&W'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('^Saturation')));
      await tester.pumpAndSettle();
      expect(find.text('No effect on B&W'), findsOneWidget);
      expect(find.byType(ShadSlider), findsOneWidget);
      expect(
        tester.widget<ShadSlider>(find.byType(ShadSlider)).enabled,
        isFalse,
      );
    });
  });
}
