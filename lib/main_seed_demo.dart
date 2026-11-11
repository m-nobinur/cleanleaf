import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/router/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'features/enhance/data/enhance_providers.dart';
import 'features/enhance/presentation/enhance_screen.dart';
import 'features/library/data/library_providers.dart';
import 'main_render_bench.dart';

// Debug probe: seeds one document and opens the enhance screen on it.
// `--dart-define=SEED_IMAGE=<path readable on the device>` uses a real photo;
// without it a synthetic shadowed page is generated.
const _seedImage = String.fromEnvironment('SEED_IMAGE');

const _demoQuad = (
  topLeft: (x: 0.17, y: 0.18),
  topRight: (x: 0.75, y: 0.18),
  bottomRight: (x: 0.75, y: 0.78),
  bottomLeft: (x: 0.17, y: 0.78),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  final original = _seedImage.isEmpty
      ? await container
            .read(pageRendererProvider)
            .thumbnail(
              syntheticPageBmp(2040, 1536, quad: _demoQuad, shadow: 0.55),
              maxSide: 2040,
            )
      : await File(_seedImage).readAsBytes();
  final document = await container
      .read(documentRepositoryProvider)
      .create('Enhance demo');
  final page = await container
      .read(pageRepositoryProvider)
      .add(
        document.id,
        original: Stream.value(original),
        detectedCorners: _seedImage.isEmpty ? _demoQuad : null,
      );
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
