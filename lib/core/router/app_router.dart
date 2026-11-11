import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/capture/presentation/capture_screen.dart';
import '../../features/editor/presentation/editor_screen.dart';
import '../../features/enhance/presentation/enhance_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import 'app_routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: AppRoutes.library,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.capture,
        builder: (context, state) => const CaptureScreen(),
      ),
      GoRoute(
        path: '/editor/:pageId',
        builder: (context, state) =>
            EditorScreen(pageId: state.pathParameters['pageId']!),
      ),
      GoRoute(
        path: '/enhance/:pageId',
        builder: (context, state) =>
            EnhanceScreen(pageId: state.pathParameters['pageId']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
