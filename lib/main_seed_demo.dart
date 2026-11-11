import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/geometry/quad.dart';
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
// `--dart-define=SEED_QUAD=x,y,x,y,x,y,x,y` (TL, TR, BR, BL, normalized) crops
// the real photo; CLSEED adjust lines time the Adjust panel's renders.
const _seedImage = String.fromEnvironment('SEED_IMAGE');
const _seedQuad = String.fromEnvironment('SEED_QUAD');

Quad? _parseQuad(String text) {
  if (text.isEmpty) return null;
  final v = text.split(',').map(double.parse).toList();
  if (v.length != 8) return null;
  return (
    topLeft: (x: v[0], y: v[1]),
    topRight: (x: v[2], y: v[3]),
    bottomRight: (x: v[4], y: v[5]),
    bottomLeft: (x: v[6], y: v[7]),
  );
}

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
  await _logAdjustTimings(renderer, 'page', path, page.corners);
  // Camera-sized input for the latency budget; timed only, never shown.
  final synthetic = File('${Directory.systemTemp.path}/adjust_12mp.jpg')
    ..writeAsBytesSync(
      await renderer.thumbnail(
        syntheticPageBmp(4080, 3072, quad: _demoQuad, shadow: 0.55),
        maxSide: 4080,
      ),
    );
  await _logAdjustTimings(renderer, '12mp', synthetic.path, _demoQuad);
}

// Slider-to-preview latency is the 40 ms debounce plus one 800 px render;
// release shows the 1600 px render.
Future<void> _logAdjustTimings(
  PageRenderer renderer,
  String label,
  String path,
  Quad quad,
) async {
  const tone = {'brightness': 0.3, 'contrast': 0.2, 'sharpness': 0.4};
  Future<void> timed(
    String name,
    Map<String, double> params,
    int side, {
    bool png = false,
    int runs = 5,
  }) async {
    final times = <int>[];
    var bytes = 0;
    for (var i = 0; i < runs; i++) {
      final watch = Stopwatch()..start();
      final out = await renderer.render(
        path,
        quad,
        0,
        PageFilter.enhancedColor,
        params,
        maxLongSide: side,
        png: png,
      );
      times.add(watch.elapsedMilliseconds);
      bytes = out.length;
    }
    times.sort();
    debugPrint(
      'CLSEED adjust $label $name median=${times[times.length ~/ 2]} '
      'max=${times.last} ms out=$bytes B',
    );
  }

  await timed('drag 800 tone', tone, 800);
  await timed('drag 800 straighten', {...tone, 'straighten': 7.5}, 800);
  await timed('release 1600', {...tone, 'straighten': 7.5}, 1600);
  await timed('full jpeg', tone, 0, runs: 2);
  await timed('full png', tone, 0, png: true, runs: 2);
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
        detectedCorners: original.synthetic ? _demoQuad : _parseQuad(_seedQuad),
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
