import 'dart:typed_data';

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/editor/presentation/editor_providers.dart';
import 'package:cleanleaf/features/editor/presentation/editor_screen.dart';
import 'package:cleanleaf/features/library/data/library_providers.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/library/domain/page_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:shadcn_ui/shadcn_ui.dart';

const Quad inset = (
  topLeft: (x: 0.2, y: 0.2),
  topRight: (x: 0.8, y: 0.2),
  bottomRight: (x: 0.8, y: 0.8),
  bottomLeft: (x: 0.2, y: 0.8),
);

const Quad detected = (
  topLeft: (x: 0.1, y: 0.1),
  topRight: (x: 0.9, y: 0.12),
  bottomRight: (x: 0.88, y: 0.9),
  bottomLeft: (x: 0.12, y: 0.88),
);

class FakePageRepository extends Fake implements PageRepository {
  FakePageRepository(this.page);

  final DocumentPage page;
  DocumentPage? saved;

  @override
  Future<DocumentPage?> get(String pageId) async =>
      pageId == page.id ? page : null;

  @override
  Future<void> updateEdits(DocumentPage page) async => saved = page;
}

final _png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 3)));

Future<FakePageRepository> pumpEditor(
  WidgetTester tester, {
  Quad? detectedCorners = detected,
}) async {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakePageRepository(
    DocumentPage(
      'p1',
      documentId: 'd1',
      index: 0,
      originalPath: 'docs/d1/p1/original.jpg',
      corners: inset,
      detectedCorners: detectedCorners,
    ),
  );
  final router = GoRouter(
    initialLocation: '/editor/p1',
    routes: [
      GoRoute(
        path: '/editor/:pageId',
        builder: (_, state) =>
            EditorScreen(pageId: state.pathParameters['pageId']!),
      ),
      GoRoute(
        path: '/enhance/:pageId',
        builder: (_, _) => const Text('Enhance stub'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pageRepositoryProvider.overrideWithValue(repo),
        pageImageProvider.overrideWith(
          (ref, path) async =>
              (image: MemoryImage(_png), size: const Size(400, 300)),
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
  return repo;
}

Future<void> drag(WidgetTester tester, String handle, Offset by) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.bySemanticsLabel(handle)),
  );
  // Two steps: the first one clears the pan slop.
  await gesture.moveBy(by / 2);
  await tester.pump();
  await gesture.moveBy(by / 2);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

Size imageSize(WidgetTester tester) => tester.getSize(find.byType(Image));

Finder get continueButton => find.widgetWithText(ShadButton, 'Continue');

Future<void> tapContinue(WidgetTester tester) async {
  await tester.tap(continueButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dragging a corner moves only that corner and saves it', (
    tester,
  ) async {
    final repo = await pumpEditor(tester);
    final size = imageSize(tester);

    await drag(tester, 'Top left corner', const Offset(40, 30));
    await tapContinue(tester);

    final corners = repo.saved!.corners;
    expect(corners.topLeft.x, closeTo(0.2 + 40 / size.width, 1e-6));
    expect(corners.topLeft.y, closeTo(0.2 + 30 / size.height, 1e-6));
    expect(corners.topRight, inset.topRight);
    expect(corners.bottomRight, inset.bottomRight);
    expect(corners.bottomLeft, inset.bottomLeft);
    expect(find.text('Enhance stub'), findsOneWidget);
  });

  testWidgets('dragging an edge midpoint moves the whole edge', (tester) async {
    final repo = await pumpEditor(tester);
    final size = imageSize(tester);

    await drag(tester, 'Right edge', const Offset(-40, 0));
    await tapContinue(tester);

    final corners = repo.saved!.corners;
    expect(corners.topRight.x, closeTo(0.8 - 40 / size.width, 1e-6));
    expect(corners.bottomRight.x, closeTo(0.8 - 40 / size.width, 1e-6));
    expect(corners.topRight.y, closeTo(0.2, 1e-6));
    expect(corners.topLeft, inset.topLeft);
  });

  testWidgets('a corner dragged off the image is clamped to its border', (
    tester,
  ) async {
    final repo = await pumpEditor(tester);

    await drag(tester, 'Top left corner', const Offset(-400, -400));
    await tapContinue(tester);

    expect(repo.saved!.corners.topLeft, (x: 0.0, y: 0.0));
  });

  testWidgets('a non-convex quad warns and disables Continue', (tester) async {
    final repo = await pumpEditor(tester);
    final warning = find.text('Corners overlap. Adjust them to continue.');
    double warningOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: warning, matching: find.byType(AnimatedOpacity)),
        )
        .opacity;
    expect(warningOpacity(), 0);

    final from = tester.getCenter(find.bySemanticsLabel('Top left corner'));
    final to = tester.getCenter(find.bySemanticsLabel('Bottom right corner'));
    await drag(tester, 'Top left corner', (to - from) * 1.2);
    await tester.pumpAndSettle();

    expect(warningOpacity(), 1);
    expect(tester.widget<ShadButton>(continueButton).enabled, isFalse);
    await tester.tap(continueButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repo.saved, isNull);
  });

  testWidgets('Reset restores the detected corners', (tester) async {
    final repo = await pumpEditor(tester);

    await drag(tester, 'Top left corner', const Offset(40, 30));
    await tester.tap(find.byIcon(LucideIcons.scanLine));
    await tester.pump();
    await tapContinue(tester);

    expect(repo.saved!.corners, detected);
  });

  testWidgets('Reset without a detection restores the full frame', (
    tester,
  ) async {
    final repo = await pumpEditor(tester, detectedCorners: null);

    await tester.tap(find.byIcon(LucideIcons.scanLine));
    await tester.pump();
    await tapContinue(tester);

    expect(repo.saved!.corners, fullFrame);
  });

  testWidgets('Full image selects the whole frame', (tester) async {
    final repo = await pumpEditor(tester);

    await tester.tap(find.byIcon(LucideIcons.maximize));
    await tester.pump();
    await tapContinue(tester);

    expect(repo.saved!.corners, fullFrame);
  });

  testWidgets('Rotate turns the view; drags still map to the original', (
    tester,
  ) async {
    final repo = await pumpEditor(tester);

    await tester.tap(find.byIcon(LucideIcons.rotateCw));
    await tester.pumpAndSettle();
    final size = imageSize(tester);
    // Turned 90° clockwise, screen-down is the original image's +x.
    await drag(tester, 'Top left corner', const Offset(0, 40));
    await tapContinue(tester);

    expect(repo.saved!.rotation, 90);
    expect(repo.saved!.corners.topLeft.x, closeTo(0.2 + 40 / size.width, 1e-6));
    expect(repo.saved!.corners.topLeft.y, closeTo(0.2, 1e-6));
  });

  testWidgets('handles have 48 dp touch targets', (tester) async {
    await pumpEditor(tester);
    expect(
      tester.getSize(find.bySemanticsLabel('Top left corner')),
      const Size(48, 48),
    );
  });
}
