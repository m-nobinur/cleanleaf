import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/core/storage/file_store.dart';
import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/capture/presentation/confirm_screen.dart';
import 'package:cleanleaf/features/enhance/data/enhance_providers.dart';
import 'package:cleanleaf/features/enhance/domain/page_renderer.dart';
import 'package:cleanleaf/features/library/data/library_providers.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/features/library/domain/page_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../library/presentation/fakes.dart';

class _Pages extends Fake implements PageRepository {
  _Pages(this.page);

  DocumentPage page;

  @override
  Future<DocumentPage?> get(String pageId) async => page;
}

class _Renderer extends Fake implements PageRenderer {
  final quads = <Quad>[];
  final filters = <PageFilter>[];

  @override
  Future<Uint8List> render(
    String originalPath,
    Quad quad,
    int rotation,
    PageFilter filter,
    Map<String, double> params, {
    int maxLongSide = 0,
  }) async {
    quads.add(quad);
    filters.add(filter);
    return Uint8List.fromList(img.encodePng(img.Image(width: 3, height: 4)));
  }
}

const Quad edited = (
  topLeft: (x: 0.1, y: 0.1),
  topRight: (x: 0.9, y: 0.1),
  bottomRight: (x: 0.9, y: 0.9),
  bottomLeft: (x: 0.1, y: 0.9),
);

void main() {
  late FakeDocumentRepository documents;
  late _Pages pages;
  late _Renderer renderer;
  late GoRouter router;

  Future<void> pumpConfirm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    documents = FakeDocumentRepository([fakeDocument('d1', 'Scan')]);
    pages = _Pages(fakePage('p1', 'd1', 0));
    renderer = _Renderer();
    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('camera')),
        GoRoute(
          path: '/confirm/:pageId',
          builder: (_, state) =>
              ConfirmScreen(pageId: state.pathParameters['pageId']!),
        ),
        GoRoute(
          path: '/editor/:pageId',
          builder: (_, state) =>
              Text('editor:${state.pathParameters['pageId']}'),
        ),
        GoRoute(
          path: '/enhance/:pageId',
          builder: (_, state) =>
              Text('enhance:${state.pathParameters['pageId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(documents),
          pageRepositoryProvider.overrideWithValue(pages),
          pageRendererProvider.overrideWithValue(renderer),
          fileStoreProvider.overrideWithValue(
            FileStore(() async => Directory.systemTemp),
          ),
        ],
        child: ShadApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    unawaited(router.push('/confirm/p1'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the cropped page uncoloured', (tester) async {
    await pumpConfirm(tester);
    expect(find.bySemanticsLabel(RegExp('Scanned page')), findsOneWidget);
    expect(renderer.filters, [PageFilter.original]);
  });

  testWidgets('retake deletes the scan and goes back to the camera', (
    tester,
  ) async {
    await pumpConfirm(tester);
    await tester.tap(find.bySemanticsLabel('Retake'));
    await tester.pumpAndSettle();
    expect(documents.deleted, ['d1']);
    expect(find.text('camera'), findsOneWidget);
  });

  testWidgets('system back also discards the scan', (tester) async {
    await pumpConfirm(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(documents.deleted, ['d1']);
    expect(find.text('camera'), findsOneWidget);
  });

  testWidgets('confirm opens enhance and keeps the scan', (tester) async {
    await pumpConfirm(tester);
    await tester.tap(find.bySemanticsLabel('Use this scan'));
    await tester.pumpAndSettle();
    expect(find.text('enhance:p1'), findsOneWidget);
    expect(documents.deleted, isEmpty);
  });

  testWidgets('tapping the page opens the editor and re-crops on return', (
    tester,
  ) async {
    await pumpConfirm(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('Scanned page')));
    await tester.pumpAndSettle();
    expect(find.text('editor:p1'), findsOneWidget);

    pages.page = pages.page.copyWith(corners: edited);
    router.pop();
    await tester.pumpAndSettle();
    expect(renderer.quads.last, edited);
  });
}
