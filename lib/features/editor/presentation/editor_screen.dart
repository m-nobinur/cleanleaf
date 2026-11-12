import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/geometry/quad.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/round_icon_button.dart';
import '../../capture/presentation/capture_controls.dart';
import '../../library/data/library_providers.dart';
import '../../library/domain/document_page.dart';
import '../domain/quad_geometry.dart';
import 'crop_canvas.dart';
import 'editor_providers.dart';

/// Crop review: straight after a capture or import ([fresh]), or to re-crop a
/// saved page. Leaving a fresh review deletes its new document (D-50).
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.pageId, this.fresh = false});

  final String pageId;
  final bool fresh;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  bool _leaving = false;

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      if (widget.fresh) {
        final page = await ref.read(pageRepositoryProvider).get(widget.pageId);
        if (page != null) {
          await ref.read(documentRepositoryProvider).delete(page.documentId);
        }
      }
    } finally {
      if (mounted) {
        context.canPop() ? context.pop() : context.go(AppRoutes.library);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return PopScope(
      canPop: !widget.fresh,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: DefaultTextStyle.merge(
          style: TextStyle(color: colors.foreground),
          child: SafeArea(child: _body(context)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final pageAsync = ref.watch(editorPageProvider(widget.pageId));
    final page = pageAsync.hasError ? null : pageAsync.value;
    final imageAsync = page == null
        ? null
        : ref.watch(pageImageProvider(page.originalPath));
    if (pageAsync.hasError || (imageAsync?.hasError ?? false)) {
      return Center(
        child: Text(
          "Couldn't open this page.",
          style: ShadTheme.of(context).textTheme.muted.copyWith(
            color: ShadTheme.of(context).colorScheme.mutedForeground,
          ),
        ),
      );
    }
    final image = imageAsync?.value;
    if (page == null || image == null) return const SizedBox.shrink();
    return _Editor(
      page: page,
      image: image,
      exit: _exitAction(page),
      onExit: _leave,
    );
  }

  ({String label, IconData icon}) _exitAction(DocumentPage page) {
    if (!widget.fresh) return (label: 'Back', icon: LucideIcons.arrowLeft);
    return page.source == PageSource.gallery
        ? (label: 'Discard', icon: LucideIcons.x)
        : (label: 'Retake', icon: LucideIcons.camera);
  }
}

typedef _Snapshot = ({Quad quad, int rotation});

class _Editor extends ConsumerStatefulWidget {
  const _Editor({
    required this.page,
    required this.image,
    required this.exit,
    required this.onExit,
  });

  final DocumentPage page;
  final PageImage image;
  final ({String label, IconData icon}) exit;
  final VoidCallback onExit;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late final _quad = ValueNotifier<Quad>(widget.page.corners);
  // Derived notifiers rebuild their widgets only when the value flips, not on
  // every drag frame.
  late final _valid = ValueNotifier(isValidQuad(widget.page.corners));
  late final _cropTarget = ValueNotifier(_targetFor(widget.page.corners));
  late int _rotation = widget.page.rotation;
  final _history = <_Snapshot>[];
  // Bumped when the crop jumps (toggle, undo, rotate) so the view refits.
  var _refits = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _quad.addListener(() {
      _valid.value = isValidQuad(_quad.value);
      _cropTarget.value = _targetFor(_quad.value);
    });
  }

  @override
  void dispose() {
    _quad.dispose();
    _valid.dispose();
    _cropTarget.dispose();
    super.dispose();
  }

  /// Where the crop toggle goes from [quad]: the detected corners and the full
  /// frame swap; with no detection only the full frame exists (null when there).
  Quad? _targetFor(Quad quad) {
    final detected = widget.page.detectedCorners;
    if (detected != null) return quad == detected ? fullFrame : detected;
    return quad == fullFrame ? null : fullFrame;
  }

  void _remember() =>
      setState(() => _history.add((quad: _quad.value, rotation: _rotation)));

  void _undo() {
    final last = _history.removeLast();
    _quad.value = last.quad;
    setState(() {
      _rotation = last.rotation;
      _refits++;
    });
  }

  void _toggleCrop(Quad target) {
    _remember();
    _quad.value = target;
    setState(() => _refits++);
  }

  void _rotate() {
    _remember();
    setState(() {
      _rotation = (_rotation + 90) % 360;
      _refits++;
    });
  }

  Future<void> _continue() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(pageRepositoryProvider)
          .updateEdits(
            widget.page.copyWith(corners: _quad.value, rotation: _rotation),
          );
      if (mounted) await context.push(AppRoutes.enhance(widget.page.id));
    } catch (_) {
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast.destructive(title: Text("Couldn't save the crop")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topRow(theme),
        Expanded(
          // A neutral stage between the slim rows, like the camera preview.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.muted,
              border: Border.symmetric(
                horizontal: BorderSide(color: theme.colorScheme.hairline),
              ),
            ),
            child: CropCanvas(
              key: ValueKey(_refits),
              image: widget.image.image,
              imageSize: widget.image.size,
              quarterTurns: _rotation ~/ 90,
              quad: _quad,
              onDragStart: _remember,
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        ValueListenableBuilder(
          valueListenable: _valid,
          builder: (context, valid, _) => AnimatedOpacity(
            opacity: valid ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Text(
              'Corners overlap. Adjust them to continue.',
              textAlign: TextAlign.center,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.destructive,
              ),
            ),
          ),
        ),
        _bottomBar(),
      ],
    );
  }

  Widget _topRow(ShadThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Spacing.lg,
      vertical: Spacing.xs,
    ),
    child: SizedBox(
      height: kMinInteractiveDimension,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'CROP',
            style: theme.textTheme.monoLabel.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _history.isEmpty
                  ? const SizedBox.shrink()
                  : RoundIconButton(
                      icon: LucideIcons.undo2,
                      label: 'Undo',
                      onPressed: _undo,
                    ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _bottomBar() => Padding(
    padding: const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.sm,
      Spacing.lg,
      Spacing.xl,
    ),
    child: Row(
      children: [
        LabeledIconButton(
          icon: widget.exit.icon,
          label: widget.exit.label,
          onPressed: widget.onExit,
        ),
        ValueListenableBuilder(
          valueListenable: _cropTarget,
          builder: (context, target, _) {
            final auto = target != null && target != fullFrame;
            return LabeledIconButton(
              icon: auto ? LucideIcons.scanLine : LucideIcons.maximize,
              label: auto ? 'Auto crop' : 'Full photo',
              onPressed: target == null ? null : () => _toggleCrop(target),
            );
          },
        ),
        LabeledIconButton(
          icon: LucideIcons.rotateCw,
          label: 'Rotate',
          onPressed: _rotate,
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: _valid,
            builder: (context, valid, _) => ShadButton(
              size: ShadButtonSize.lg,
              // Fits beside three 72 dp tools on a 360 dp phone.
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              enabled: valid && !_saving,
              onPressed: _continue,
              child: const Text('Continue'),
            ),
          ),
        ),
      ],
    ),
  );
}
