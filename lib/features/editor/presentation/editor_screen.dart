import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/geometry/quad.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../library/data/library_providers.dart';
import '../../library/domain/document_page.dart';
import '../domain/quad_geometry.dart';
import 'crop_canvas.dart';
import 'editor_providers.dart';

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key, required this.pageId});

  final String pageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The editor is dark (ink) in both app themes.
    return ShadTheme(
      data: AppTheme.dark,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Builder(
          builder: (context) {
            final theme = ShadTheme.of(context);
            return Scaffold(
              backgroundColor: theme.colorScheme.background,
              body: DefaultTextStyle.merge(
                style: TextStyle(color: theme.colorScheme.foreground),
                child: SafeArea(child: _body(context, ref)),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(editorPageProvider(pageId));
    final page = pageAsync.hasError ? null : pageAsync.value;
    final imageAsync = page == null
        ? null
        : ref.watch(pageImageProvider(page.originalPath));
    if (pageAsync.hasError || (imageAsync?.hasError ?? false)) {
      return Center(
        child: Text(
          "Couldn't open this page.",
          style: ShadTheme.of(context).textTheme.muted,
        ),
      );
    }
    final image = imageAsync?.value;
    if (page == null || image == null) return const SizedBox.shrink();
    return _Editor(page: page, image: image);
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.page, required this.image});

  final DocumentPage page;
  final PageImage image;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late final _quad = ValueNotifier<Quad>(widget.page.corners);
  // Rebuilds the panel only when validity flips, not on every drag frame.
  late final _valid = ValueNotifier(isValidQuad(widget.page.corners));
  late int _rotation = widget.page.rotation;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _quad.addListener(() => _valid.value = isValidQuad(_quad.value));
  }

  @override
  void dispose() {
    _quad.dispose();
    _valid.dispose();
    super.dispose();
  }

  void _retake() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.library);

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
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ShadButton.ghost(
                  foregroundColor: theme.colorScheme.foreground,
                  onPressed: _retake,
                  leading: const Icon(LucideIcons.arrowLeft),
                  child: const Text('Retake'),
                ),
              ),
              Text('Crop', style: theme.textTheme.h4),
            ],
          ),
        ),
        Expanded(
          child: CropCanvas(
            image: widget.image.image,
            imageSize: widget.image.size,
            quarterTurns: _rotation ~/ 90,
            quad: _quad,
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _valid,
          builder: (context, valid, _) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.sm,
                Spacing.lg,
                Spacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedOpacity(
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
                  const SizedBox(height: Spacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Tool(
                        icon: LucideIcons.scanLine,
                        label: 'Reset',
                        onPressed: () => _quad.value =
                            widget.page.detectedCorners ?? fullFrame,
                      ),
                      _Tool(
                        icon: LucideIcons.maximize,
                        label: 'Full image',
                        onPressed: () => _quad.value = fullFrame,
                      ),
                      _Tool(
                        icon: LucideIcons.rotateCw,
                        label: 'Rotate',
                        onPressed: () =>
                            setState(() => _rotation = (_rotation + 90) % 360),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.lg),
                  ShadButton(
                    size: ShadButtonSize.lg,
                    enabled: valid && !_saving,
                    onPressed: _continue,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadIconButton.outline(
            width: kMinInteractiveDimension,
            height: kMinInteractiveDimension,
            icon: Icon(icon),
            onPressed: onPressed,
          ),
          const SizedBox(height: Spacing.xs),
          Text(label, style: theme.textTheme.muted),
        ],
      ),
    );
  }
}
