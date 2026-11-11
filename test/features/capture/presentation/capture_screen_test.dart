import 'dart:async';

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/capture/data/camera_scan.dart';
import 'package:cleanleaf/features/capture/data/capture_providers.dart';
import 'package:cleanleaf/features/capture/domain/document_camera.dart';
import 'package:cleanleaf/features/capture/domain/scan_mode.dart';
import 'package:cleanleaf/features/capture/presentation/capture_screen.dart';
import 'package:cleanleaf/features/gallery_import/data/gallery_import.dart';
import 'package:cleanleaf/features/gallery_import/presentation/import_from_gallery.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../library/presentation/fakes.dart';
import 'fake_camera.dart';

class FakeScan extends Fake implements CameraScan {
  final calls = <({String still, ScanMode mode, Quad? liveQuad})>[];

  @override
  Future<DocumentPage> call(
    String stillPath, {
    required ScanMode mode,
    Quad? liveQuad,
  }) async {
    calls.add((still: stillPath, mode: mode, liveQuad: liveQuad));
    return fakePage('p${calls.length}', 'd${calls.length}', 0);
  }
}

const Quad page = (
  topLeft: (x: 0.2, y: 0.2),
  topRight: (x: 0.8, y: 0.2),
  bottomRight: (x: 0.8, y: 0.8),
  bottomLeft: (x: 0.2, y: 0.8),
);

void main() {
  late FakeCamera camera;
  late FakeScan scan;
  late GoRouter router;
  Completer<String?>? pick;

  Future<void> pumpCapture(
    WidgetTester tester, {
    ScanMode mode = ScanMode.document,
    CameraPermission permission = CameraPermission.granted,
  }) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    camera = FakeCamera()..permission = permission;
    scan = FakeScan();
    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/capture',
          builder: (_, state) => CaptureScreen(
            mode: ScanMode.parse(state.uri.queryParameters['mode']),
          ),
        ),
        GoRoute(
          path: '/confirm/:pageId',
          builder: (_, state) =>
              Text('confirm:${state.pathParameters['pageId']}'),
        ),
        GoRoute(
          path: '/editor/:pageId',
          builder: (_, state) =>
              Text('editor:${state.pathParameters['pageId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentCameraProvider.overrideWithValue(camera),
          cameraScanProvider.overrideWithValue(scan),
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
          galleryImportProvider.overrideWithValue(
            GalleryImport(
              pick: () => (pick = Completer<String?>()).future,
              detect: (_) async => null,
              documents: FakeDocumentRepository(),
              pages: FakePageRepository(),
            ),
          ),
        ],
        child: ShadApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    unawaited(router.push('/capture?mode=${mode.name}'));
    await tester.pump();
    await tester.pump();
  }

  // The pill's pulse repeats forever, so settle with fixed pumps.
  Future<void> emit(
    WidgetTester tester,
    Quad? quad, {
    bool stable = false,
  }) async {
    camera.frames.add((quad: quad, confidence: 0.9, isStable: stable));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pop(WidgetTester tester) async {
    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('starts the preview once the camera is allowed', (tester) async {
    await pumpCapture(tester);
    expect(camera.starts, 1);
    expect(find.byType(Texture), findsOneWidget);
    expect(find.bySemanticsLabel('Take photo'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
  });

  testWidgets('a denial explains why and can ask again', (tester) async {
    await pumpCapture(tester);
    camera.permission = CameraPermission.denied;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Allow camera'), findsOneWidget);

    camera.permission = CameraPermission.granted;
    await tester.tap(find.text('Allow camera'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('a permanent denial opens settings and starts on return', (
    tester,
  ) async {
    await pumpCapture(tester, permission: CameraPermission.permanentlyDenied);
    expect(camera.starts, 0);
    expect(find.text('Open settings'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    expect(camera.openedSettings, isTrue);
    camera.permission = CameraPermission.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('holds still, then auto-captures once per stable page', (
    tester,
  ) async {
    await pumpCapture(tester);
    await emit(tester, page);
    expect(find.text('Hold still'), findsOneWidget);

    await emit(tester, page, stable: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(camera.captures, 1);
    expect(scan.calls.single.liveQuad, page);
    expect(scan.calls.single.mode, ScanMode.document);
    expect(find.text('confirm:p1'), findsOneWidget);
    expect(camera.stops, 1, reason: 'camera is off under the confirm screen');

    await pop(tester);
    expect(camera.starts, 2);
    // The same page, still resting there after a retake, is not shot again.
    await emit(tester, page, stable: true);
    await emit(tester, page, stable: true);
    expect(camera.captures, 1);
    expect(find.text('Hold still'), findsNothing);
  });

  testWidgets('with auto-capture off only the shutter shoots', (tester) async {
    await pumpCapture(tester);
    await tester.tap(find.bySemanticsLabel('Auto-capture'));
    await emit(tester, page, stable: true);
    expect(camera.captures, 0);
    expect(find.text('Hold still'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Take photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(camera.captures, 1);
    expect(find.text('confirm:p1'), findsOneWidget);
  });

  testWidgets('restarts the camera when the app comes back', (tester) async {
    await pumpCapture(tester);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(find.byType(Texture), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(camera.starts, 2);
    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('keeps the camera off while importing a photo', (tester) async {
    await pumpCapture(tester);
    await tester.tap(find.bySemanticsLabel('Import'));
    await tester.pump();
    expect(camera.stops, 1);
    // Returning from the picker resumes the app, but the import still owns
    // the screen, so the camera must not start under it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(camera.starts, 1);

    pick!.complete(null);
    await tester.pump();
    await tester.pump();
    expect(camera.starts, 2);
  });

  testWidgets('torch and tap-to-focus reach the camera', (tester) async {
    await pumpCapture(tester);
    await tester.tap(find.bySemanticsLabel('Turn torch on'));
    await tester.pump();
    expect(camera.torch, [true]);
    expect(find.bySemanticsLabel('Turn torch off'), findsOneWidget);

    final preview = tester.getRect(find.byType(Texture));
    await tester.tapAt(preview.center);
    await tester.pump();
    expect(camera.focused.single.x, closeTo(0.5, 0.01));
    expect(camera.focused.single.y, closeTo(0.5, 0.01));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a start failure offers a retry', (tester) async {
    await pumpCapture(tester);
    camera.startFailure = CameraFailure.unavailable;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text("The camera couldn't start"), findsOneWidget);

    camera.startFailure = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('receipt mode labels import "Add" and captures as a receipt', (
    tester,
  ) async {
    await pumpCapture(tester, mode: ScanMode.receipt);
    expect(find.text('Add'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Take photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(scan.calls.single.mode, ScanMode.receipt);
  });

  testWidgets('switching mode in the camera changes the capture mode', (
    tester,
  ) async {
    await pumpCapture(tester);
    await tester.tap(find.bySemanticsLabel('ID card mode'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('Take photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(scan.calls.single.mode, ScanMode.idCard);
  });
}
