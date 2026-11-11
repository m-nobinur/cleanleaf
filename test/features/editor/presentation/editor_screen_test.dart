import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/editor/presentation/crop_canvas.dart';
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

import '../../library/presentation/fakes.dart' show FakeDocumentRepository;

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

late FakeDocumentRepository documents;

Future<FakePageRepository> pumpEditor(
  WidgetTester tester, {
  Quad corners = inset,
  Quad? detectedCorners = detected,
  Size pageSize = const Size(400, 300),
  bool fresh = false,
  PageSource source = PageSource.camera,
}) async {
  tester.view
    ..physicalSize = const Size(1236, 2745)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakePageRepository(
    DocumentPage(
      'p1',
      documentId: 'd1',
      index: 0,
      originalPath: 'docs/d1/p1/original.jpg',
      corners: corners,
      detectedCorners: detectedCorners,
      source: source,
    ),
  );
  documents = FakeDocumentRepository();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('camera')),
      GoRoute(
        path: '/editor/:pageId',
        builder: (_, state) => EditorScreen(
          pageId: state.pathParameters['pageId']!,
          fresh: state.uri.queryParameters['fresh'] == '1',
        ),
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
        documentRepositoryProvider.overrideWithValue(documents),
        pageImageProvider.overrideWith(
          (ref, path) async => (image: MemoryImage(_png), size: pageSize),
        ),
      ],
      child: ShadApp.router(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        routerConfig: router,
      ),
    ),
  );
  unawaited(router.push(fresh ? '/editor/p1?fresh=1' : '/editor/p1'));
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

Future<void> tapLabel(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}

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

  testWidgets('the crop toggle swaps detected corners and the full photo', (
    tester,
  ) async {
    final repo = await pumpEditor(tester, corners: detected);
    expect(find.bySemanticsLabel('Auto crop'), findsNothing);

    await tapLabel(tester, 'Full photo');
    expect(find.bySemanticsLabel('Full photo'), findsNothing);
    await tapLabel(tester, 'Auto crop');
    await tapLabel(tester, 'Full photo');
    await tapContinue(tester);

    expect(repo.saved!.corners, fullFrame);
  });

  testWidgets('after a manual edit the toggle restores auto crop', (
    tester,
  ) async {
    final repo = await pumpEditor(tester, corners: detected);

    await drag(tester, 'Top left corner', const Offset(40, 30));
    await tapLabel(tester, 'Auto crop');
    await tapContinue(tester);

    expect(repo.saved!.corners, detected);
  });

  testWidgets('without a detection only Full photo exists', (tester) async {
    final repo = await pumpEditor(tester, detectedCorners: null);
    bool enabled() =>
        tester
            .getSemantics(find.bySemanticsLabel('Full photo'))
            .flagsCollection
            .isEnabled ==
        Tristate.isTrue;
    expect(enabled(), isTrue);

    await tapLabel(tester, 'Full photo');

    expect(find.bySemanticsLabel('Auto crop'), findsNothing);
    expect(enabled(), isFalse);
    await tapContinue(tester);
    expect(repo.saved!.corners, fullFrame);
  });

  testWidgets('undo appears after an edit and steps back through edits', (
    tester,
  ) async {
    final repo = await pumpEditor(tester, corners: detected);
    expect(find.bySemanticsLabel('Undo'), findsNothing);

    await drag(tester, 'Top left corner', const Offset(40, 30));
    await tapLabel(tester, 'Rotate');
    await tapLabel(tester, 'Undo');
    expect(find.bySemanticsLabel('Undo'), findsOneWidget);
    await tapLabel(tester, 'Undo');
    expect(find.bySemanticsLabel('Undo'), findsNothing);
    await tapContinue(tester);

    expect(repo.saved!.corners, detected);
    expect(repo.saved!.rotation, 0);
  });

  testWidgets('retake on a fresh scan deletes it and goes back', (
    tester,
  ) async {
    await pumpEditor(tester, fresh: true);
    await tapLabel(tester, 'Retake');
    expect(documents.deleted, ['d1']);
    expect(find.text('camera'), findsOneWidget);
  });

  testWidgets('system back also discards a fresh scan', (tester) async {
    await pumpEditor(tester, fresh: true);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(documents.deleted, ['d1']);
    expect(find.text('camera'), findsOneWidget);
  });

  testWidgets('a fresh import offers Discard instead of Retake', (
    tester,
  ) async {
    await pumpEditor(tester, fresh: true, source: PageSource.gallery);
    expect(find.bySemanticsLabel('Retake'), findsNothing);
    await tapLabel(tester, 'Discard');
    expect(documents.deleted, ['d1']);
  });

  testWidgets('re-cropping a saved page never deletes it', (tester) async {
    await pumpEditor(tester);
    await tapLabel(tester, 'Back');
    expect(find.text('camera'), findsOneWidget);
    expect(documents.deleted, isEmpty);
  });

  testWidgets('Rotate turns the view; drags still map to the original', (
    tester,
  ) async {
    final repo = await pumpEditor(tester);

    await tapLabel(tester, 'Rotate');
    final size = imageSize(tester);
    // Turned 90° clockwise: the original top-left shows at the top right,
    // and screen-down is the original image's +x.
    await drag(tester, 'Top right corner', const Offset(0, 40));
    await tapContinue(tester);

    expect(repo.saved!.rotation, 90);
    expect(repo.saved!.corners.topLeft.x, closeTo(0.2 + 40 / size.width, 1e-6));
    expect(repo.saved!.corners.topLeft.y, closeTo(0.2, 1e-6));
  });

  testWidgets('opens zoomed to the page; double-tap swaps photo and page', (
    tester,
  ) async {
    await pumpEditor(tester);
    final stage = tester.getSize(find.byType(CropCanvas));
    final page = imageSize(tester);
    expect(page.width, greaterThan(stage.width), reason: 'zoomed in');

    Future<void> doubleTap() async {
      await tester.tap(find.byType(CropCanvas));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(CropCanvas));
      await tester.pumpAndSettle();
    }

    await doubleTap();
    expect(imageSize(tester).width, lessThan(stage.width));

    await doubleTap();
    expect(imageSize(tester).width, closeTo(page.width, 1e-6));
  });

  testWidgets('a full-frame crop opens on the whole photo', (tester) async {
    await pumpEditor(tester, corners: fullFrame);
    expect(
      imageSize(tester).width,
      lessThan(tester.getSize(find.byType(CropCanvas)).width),
    );
  });

  testWidgets('pinching zooms the photo', (tester) async {
    await pumpEditor(tester, corners: fullFrame);
    final before = imageSize(tester).width;
    final center = tester.getCenter(find.byType(CropCanvas));
    // Diagonal, clear of the edge-midpoint handles.
    final a = await tester.startGesture(center - const Offset(50, 40));
    final b = await tester.startGesture(center + const Offset(50, 40));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await a.moveBy(const Offset(-25, -20));
      await b.moveBy(const Offset(25, 20));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(imageSize(tester).width, greaterThan(before * 1.2));
  });

  testWidgets('handles have 48 dp touch targets', (tester) async {
    await pumpEditor(tester);
    expect(
      tester.getSize(find.bySemanticsLabel('Top left corner')),
      const Size(48, 48),
    );
  });
}
