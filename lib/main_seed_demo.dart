import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/router/app_routes.dart';
import 'core/storage/storage_providers.dart';
import 'core/theme/app_theme.dart';
import 'features/enhance/data/enhance_providers.dart';
import 'features/enhance/domain/page_renderer.dart';
import 'features/enhance/presentation/enhance_screen.dart';
import 'features/library/data/library_providers.dart';
import 'features/library/domain/document_page.dart';
import 'main_render_bench.dart';

// Release probe: seeds one 12 MP page, logs CLSEED render timings (read with
// `adb logcat -s flutter:I`) and opens the enhance screen on it.
// `--dart-define=SEED_IMAGE=<path readable on the device>` uses a real photo;
// without it, or if it can't be read, a synthetic shadowed page is generated.
const _seedImage = String.fromEnvironment('SEED_IMAGE');

const _demoQuad = (
  topLeft: (x: 0.17, y: 0.18),
  topRight: (x: 0.75, y: 0.18),
  bottomRight: (x: 0.75, y: 0.78),
  bottomLeft: (x: 0.17, y: 0.78),
);

Future<({Uint8List bytes, bool synthetic})> _loadOriginal(
  PageRenderer renderer,
) async {
  if (_seedImage.isNotEmpty) {
    try {
      final bytes = await File(_seedImage).readAsBytes();
      debugPrint('CLSEED source=file $_seedImage');
      return (bytes: bytes, synthetic: false);
    } catch (e) {
      debugPrint('CLSEED file unreadable ($e), using synthetic');
    }
  }
  debugPrint('CLSEED source=synthetic 4080x3072');
  final jpeg = await renderer.thumbnail(
    syntheticPageBmp(4080, 3072, quad: _demoQuad, shadow: 0.55),
    maxSide: 4080,
  );
  return (bytes: jpeg, synthetic: true);
}

Future<void> _logTimings(ProviderContainer container, DocumentPage page) async {
  final renderer = container.read(pageRendererProvider);
  final path =
      (await container.read(fileStoreProvider).resolve(page.originalPath)).path;
  Future<void> timed(String name, PageFilter filter, int side) async {
    final watch = Stopwatch()..start();
    await renderer.render(
      path,
      page.corners,
      0,
      filter,
      const {},
      maxLongSide: side,
    );
    debugPrint('CLSEED $name ${watch.elapsedMilliseconds} ms');
  }

  // The screen's opening burst: one preview and four chip thumbnails at once.
  final burst = Stopwatch()..start();
  await Future.wait([
    timed('burst preview', PageFilter.enhancedColor, 1600),
    for (final f in PageFilter.values) timed('burst chip ${f.name}', f, 400),
  ]);
  debugPrint('CLSEED burst total ${burst.elapsedMilliseconds} ms');
  for (final f in PageFilter.values) {
    await timed('switch ${f.name}', f, 1600);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  final original = await _loadOriginal(container.read(pageRendererProvider));
  final document = await container
      .read(documentRepositoryProvider)
      .create('Enhance demo');
  final page = await container
      .read(pageRepositoryProvider)
      .add(
        document.id,
        original: Stream.value(original.bytes),
        detectedCorners: original.synthetic ? _demoQuad : null,
      );
  try {
    await _logTimings(container, page);
  } catch (e) {
    debugPrint('CLSEED timing failed $e');
  }
  debugPrint('CLSEED DONE');
  final router = GoRouter(
    initialLocation: AppRoutes.enhance(page.id),
    routes: [
      GoRoute(
        path: '/enhance/:pageId',
        builder: (_, state) =>
            EnhanceScreen(pageId: state.pathParameters['pageId']!),
      ),
      GoRoute(path: AppRoutes.library, builder: (_, _) => const Text('Saved')),
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ShadApp.router(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        routerConfig: router,
      ),
    ),
  );
}
