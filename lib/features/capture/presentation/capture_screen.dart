import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/metrics/scan_metrics.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/corner_brackets.dart';
import '../../../core/widgets/round_icon_button.dart';
import '../../gallery_import/presentation/import_from_gallery.dart';
import '../data/capture_providers.dart';
import '../domain/auto_capture.dart';
import '../domain/document_camera.dart';
import '../domain/scan_mode.dart';
import 'capture_controls.dart';
import 'quad_overlay.dart';
import 'scan_mode_sheet.dart';

enum _Phase { starting, live, paused, denied, blocked, failed }

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key, this.mode = ScanMode.document});

  final ScanMode mode;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  late final DocumentCamera _camera = ref.read(documentCameraProvider);
  late ScanMode _mode = widget.mode;
  final _autoCapture = AutoCapture();
  final _detection = ValueNotifier<LiveDetection?>(null);
  final _focusPoint = ValueNotifier<Offset?>(null);
  StreamSubscription<LiveDetection>? _detections;
  Timer? _focusTimer;

  _Phase _phase = _Phase.starting;
  CameraPreview? _preview;
  CameraFailure? _failure;
  bool _auto = true;
  bool _torch = false;
  bool _busy = false;
  // Another route (confirm, editor, picker) is on top; the camera stays off.
  bool _covered = false;
  bool _askingPermission = false;
  // Drops results of a start() that a pause or a newer start() superseded.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _detections = _camera.detections.listen(_onDetection, onError: _onError);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([]);
    _detections?.cancel();
    _focusTimer?.cancel();
    _generation++;
    unawaited(_camera.stop().catchError((_) {}));
    _detection.dispose();
    _focusPoint.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The permission dialog itself pauses and resumes the activity.
    if (_askingPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        // The native session ended on pause; it needs a fresh start().
        if (!_covered && _phase != _Phase.starting) _start();
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused:
        if (_phase == _Phase.live || _phase == _Phase.starting) {
          _pause();
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _open() async {
    _askingPermission = true;
    final CameraPermission permission;
    try {
      permission = await _camera.requestPermission();
    } on Object {
      if (mounted) _fail(CameraFailure.unavailable);
      return;
    } finally {
      _askingPermission = false;
    }
    if (!mounted) return;
    switch (permission) {
      case CameraPermission.granted:
        await _start();
      case CameraPermission.denied:
        setState(() => _phase = _Phase.denied);
      case CameraPermission.permanentlyDenied:
        setState(() => _phase = _Phase.blocked);
    }
  }

  Future<void> _start() async {
    final generation = ++_generation;
    final previous = _phase;
    // A permission notice stays up until the camera actually starts.
    final asking = previous == _Phase.denied || previous == _Phase.blocked;
    setState(() {
      if (!asking) _phase = _Phase.starting;
      _preview = null;
      _torch = false;
    });
    try {
      final preview = await _camera.start();
      if (!mounted || generation != _generation) return;
      setState(() {
        _preview = preview;
        _phase = _Phase.live;
        _failure = null;
      });
    } on CameraFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      if (failure == CameraFailure.permissionDenied) {
        setState(() => _phase = asking ? previous : _Phase.denied);
      } else {
        _fail(failure);
      }
    }
  }

  void _pause() {
    _generation++;
    _detection.value = null;
    setState(() {
      _phase = _Phase.paused;
      _preview = null;
    });
  }

  void _fail(CameraFailure failure) => setState(() {
    _phase = _Phase.failed;
    _failure = failure;
    _preview = null;
  });

  void _onDetection(LiveDetection detection) {
    if (_phase != _Phase.live || _busy) return;
    if (_failure == CameraFailure.inUse) setState(() => _failure = null);
    ScanMetrics.liveFrame(hasQuad: detection.quad != null);
    _detection.value = detection;
    if (_auto && _autoCapture.onDetection(detection)) _capture();
  }

  void _onError(Object error) {
    if (!mounted || error is! CameraFailure) return;
    if (error == CameraFailure.inUse) {
      _detection.value = null;
      setState(() => _failure = error);
    } else {
      _fail(error);
    }
  }

  Future<void> _capture() async {
    if (_busy || _phase != _Phase.live) return;
    final liveQuad = _detection.value?.quad;
    _autoCapture.markShot(liveQuad);
    setState(() => _busy = true);
    final watch = Stopwatch()..start();
    try {
      final still = await _camera.capture();
      final captureMs = watch.elapsedMilliseconds;
      final page = await ref.read(cameraScanProvider)(
        still,
        mode: _mode,
        liveQuad: liveQuad,
      );
      debugPrint(
        'CLMETRIC shutter_to_confirm capture_ms=$captureMs '
        'total_ms=${watch.elapsedMilliseconds}',
      );
      if (!mounted) return;
      await _cover(() => context.push(AppRoutes.confirm(page.id)));
    } on Object {
      _autoCapture.markShot(null);
      if (!mounted) return;
      ShadToaster.of(context).show(
        const ShadToast.destructive(title: Text("Couldn't take the photo")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Keeps the camera off while [route] shows another screen on top.
  Future<void> _cover(Future<void> Function() route) async {
    _covered = true;
    _pause();
    unawaited(_camera.stop().catchError((_) {}));
    try {
      await route();
    } finally {
      _covered = false;
      if (mounted) unawaited(_start());
    }
  }

  Future<void> _import() => _cover(() => importFromGallery(context, ref));

  Future<void> _toggleTorch() async {
    final on = !_torch;
    setState(() => _torch = on);
    try {
      await _camera.setTorch(on);
    } on Object {
      if (mounted) setState(() => _torch = !on);
    }
  }

  void _focus(Offset local, Size size) {
    if (_phase != _Phase.live) return;
    final point = (x: local.dx / size.width, y: local.dy / size.height);
    _focusPoint.value = local;
    _focusTimer?.cancel();
    _focusTimer = Timer(
      const Duration(milliseconds: 1200),
      () => _focusPoint.value = null,
    );
    unawaited(_camera.focusAt(point).catchError((_) => false));
  }

  void _selectMode(ScanMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    unawaited(ref.read(lastScanModeProvider.notifier).set(mode));
  }

  void _close() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.library);

  @override
  Widget build(BuildContext context) {
    final light = _mode == ScanMode.receipt;
    return ShadTheme(
      data: light ? AppTheme.light : AppTheme.dark,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        child: Builder(
          builder: (context) {
            final colors = ShadTheme.of(context).colorScheme;
            return Scaffold(
              backgroundColor: colors.background,
              body: SafeArea(
                child: Column(
                  children: [
                    _topBar(),
                    Expanded(child: _body(context)),
                    _bottomBar(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.all(Spacing.lg),
    child: Row(
      children: [
        RoundIconButton(icon: LucideIcons.x, label: 'Close', onPressed: _close),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ModeSwitch(mode: _mode, onChanged: _selectMode),
          ),
        ),
        AutoCaptureToggle(
          enabled: _auto,
          onChanged: (on) => setState(() => _auto = on),
        ),
      ],
    ),
  );

  Widget _bottomBar() {
    final hasTorch = _preview?.hasTorch ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.xl,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          LabeledIconButton(
            icon: LucideIcons.images,
            label: _mode == ScanMode.receipt ? 'Add' : 'Import',
            onPressed: _import,
          ),
          ShutterButton(
            onPressed: _phase == _Phase.live && !_busy ? _capture : null,
          ),
          SizedBox(
            width: 72,
            child: hasTorch
                ? Center(
                    child: RoundIconButton(
                      icon: _torch
                          ? LucideIcons.flashlight
                          : LucideIcons.flashlightOff,
                      label: _torch ? 'Turn torch off' : 'Turn torch on',
                      onPressed: _toggleTorch,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) => switch (_phase) {
    _Phase.denied => CameraNotice(
      title: 'Allow the camera',
      message:
          'Cleanleaf uses the camera to scan pages. '
          'Photos stay on this phone.',
      action: ShadButton(onPressed: _open, child: const Text('Allow camera')),
    ),
    _Phase.blocked => CameraNotice(
      title: 'Camera access is off',
      message:
          'Turn on the camera permission in Settings to scan pages, '
          'or import a photo instead.',
      action: ShadButton(
        onPressed: _camera.openAppSettings,
        child: const Text('Open settings'),
      ),
    ),
    _Phase.failed => CameraNotice(
      title: _failure == CameraFailure.disabled
          ? 'The camera is turned off'
          : "The camera couldn't start",
      message: _failure == CameraFailure.disabled
          ? 'A device policy or Do Not Disturb is blocking the camera.'
          : 'Close other camera apps and try again.',
      action: ShadButton.outline(
        onPressed: _start,
        child: const Text('Try again'),
      ),
    ),
    _ => _previewArea(context),
  };

  Widget _previewArea(BuildContext context) {
    final preview = _preview;
    final colors = ShadTheme.of(context).colorScheme;
    // Fit to width rather than cover: cropping 3:4 to a 20:9 screen would hide
    // about 40% of the width that the detector and the still both see.
    return Center(
      child: AspectRatio(
        aspectRatio: preview == null ? 3 / 4 : preview.width / preview.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _focus(details.localPosition, size),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: AppTheme.dark.colorScheme.background),
                  if (preview != null)
                    RotatedBox(
                      key: ValueKey(preview.textureId),
                      quarterTurns: preview.quarterTurns,
                      child: Texture(textureId: preview.textureId),
                    ),
                  AnimatedOpacity(
                    opacity: _busy ? 0.6 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: ColoredBox(color: colors.background),
                  ),
                  ValueListenableBuilder(
                    valueListenable: _detection,
                    builder: (context, detection, _) => Stack(
                      fit: StackFit.expand,
                      children: [
                        _ModeGuide(
                          mode: _mode,
                          visible: detection?.quad == null,
                        ),
                        QuadOverlay(
                          quad: detection?.quad,
                          color: colors.primary,
                        ),
                        _hint(detection),
                      ],
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: _focusPoint,
                    builder: (context, point, _) =>
                        _FocusRing(point: point, color: colors.foreground),
                  ),
                  if (_failure == CameraFailure.inUse)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.all(Spacing.lg),
                        child: _Banner('Another app is using the camera'),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _hint(LiveDetection? detection) {
    final arming =
        _auto &&
        !_busy &&
        _autoCapture.isArmed &&
        detection != null &&
        detection.quad != null &&
        !detection.isStable;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: arming ? const HoldStillPill() : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// A centred bracket guide sized to the mode's page: a tall receipt or an
/// ID-1 card. Documents have none; the live outline is the guide.
class _ModeGuide extends StatelessWidget {
  const _ModeGuide({required this.mode, required this.visible});

  static final _guide = AppTheme.dark.colorScheme;

  final ScanMode mode;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final (widthFactor, aspect) = switch (mode) {
      ScanMode.receipt => (0.5, 1 / 2.4),
      ScanMode.idCard => (0.8, 1.586),
      _ => (0.0, 1.0),
    };
    if (widthFactor == 0) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: widthFactor,
          child: AspectRatio(
            aspectRatio: aspect,
            // Light strokes on a soft ink halo read on a white receipt and on
            // a dark desk alike; the guide sits over the preview, not the frame.
            child: CornerBrackets(
              color: _guide.foreground,
              strokeWidth: 3,
              length: 0.22,
              child: CornerBrackets(
                color: _guide.background.withValues(alpha: 0.35),
                strokeWidth: 7,
                length: 0.22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusRing extends StatelessWidget {
  const _FocusRing({required this.point, required this.color});

  final Offset? point;
  final Color color;

  static const _size = 64.0;

  @override
  Widget build(BuildContext context) {
    final p = point;
    if (p == null) return const SizedBox.shrink();
    return Positioned(
      left: p.dx - _size / 2,
      top: p.dy - _size / 2,
      width: _size,
      height: _size,
      child: IgnorePointer(
        child: CornerBrackets(color: color, length: 0.3)
            .animate(key: ValueKey(p))
            .scaleXY(
              begin: 1.3,
              end: 1,
              duration: 200.ms,
              curve: Curves.easeOut,
            )
            .fadeIn(duration: 150.ms),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.card,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: theme.colorScheme.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm,
          ),
          child: Text(
            text,
            style: theme.textTheme.small.copyWith(
              color: theme.colorScheme.foreground,
            ),
          ),
        ),
      ),
    );
  }
}
