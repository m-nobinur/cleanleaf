import 'dart:io';
import 'dart:typed_data';

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/core/storage/file_store.dart';
import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/core/theme/app_theme.dart';
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
  }) async {
    calls.add((filter: filter, rotation: rotation, maxLongSide: maxLongSide));
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

  final DocumentPage page;
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
  WidgetTester tester,
) async {
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
    ),
  );
  final router = GoRouter(
    initialLocation: '/enhance/p1',
    routes: [
      GoRoute(
        path: '/enhance/:pageId',
        builder: (_, state) =>
            EnhanceScreen(pageId: state.pathParameters['pageId']!),
      ),
      GoRoute(path: '/', builder: (_, _) => const Text('Library stub')),
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
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
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
}
