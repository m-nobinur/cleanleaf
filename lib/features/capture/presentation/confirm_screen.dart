import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/corner_brackets.dart';
import '../../enhance/data/enhance_providers.dart';
import '../../library/data/library_providers.dart';
import '../../library/domain/document_page.dart';

// Sharp on a phone screen without a full-resolution render.
const _previewLongSide = 1600;

/// After a shot: the cropped page to accept, retake, or tap to fix corners.
/// The page is already saved, so retake (and back) deletes its document.
class ConfirmScreen extends ConsumerStatefulWidget {
  const ConfirmScreen({super.key, required this.pageId});

  final String pageId;

  @override
  ConsumerState<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends ConsumerState<ConfirmScreen> {
  DocumentPage? _page;
  Uint8List? _crop;
  bool _failed = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final watch = Stopwatch()..start();
    try {
      final page = await ref.read(pageRepositoryProvider).get(widget.pageId);
      if (page == null) throw StateError('Page ${widget.pageId} not found');
      if (mounted) setState(() => _page = page);
      final original = await ref
          .read(fileStoreProvider)
          .resolve(page.originalPath);
      final crop = await ref
          .read(pageRendererProvider)
          .render(
            original.path,
            page.corners,
            page.rotation,
            PageFilter.original,
            page.filterParams,
            maxLongSide: _previewLongSide,
          );
      debugPrint('CLMETRIC confirm_crop ms=${watch.elapsedMilliseconds}');
      if (mounted) {
        setState(() {
          _crop = crop;
          _failed = false;
        });
      }
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _edit() async {
    await context.push(AppRoutes.editor(widget.pageId));
    if (mounted) await _load();
  }

  Future<void> _retake() async {
    if (_leaving) return;
    _leaving = true;
    try {
      final page =
          _page ?? await ref.read(pageRepositoryProvider).get(widget.pageId);
      if (page != null) {
        await ref.read(documentRepositoryProvider).delete(page.documentId);
      }
    } finally {
      if (mounted) {
        context.canPop() ? context.pop() : context.go(AppRoutes.library);
      }
    }
  }

  void _confirm() => context.push(AppRoutes.enhance(widget.pageId));

  @override
  Widget build(BuildContext context) {
    return ShadTheme(
      data: AppTheme.dark,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _retake();
          },
          child: Builder(
            builder: (context) {
              final theme = ShadTheme.of(context);
              return Scaffold(
                backgroundColor: theme.colorScheme.background,
                body: SafeArea(
                  child: Column(
                    children: [
                      Expanded(child: _pageView(context)),
                      Text(
                        'Tap the page to adjust its corners',
                        style: theme.textTheme.caption.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(Spacing.xl),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _RoundAction(
                              icon: LucideIcons.rotateCcw,
                              label: 'Retake',
                              filled: true,
                              onPressed: _retake,
                            ),
                            const SizedBox(width: Spacing.xl),
                            _RoundAction(
                              icon: LucideIcons.check,
                              label: 'Use this scan',
                              filled: false,
                              onPressed: _page == null ? null : _confirm,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _pageView(BuildContext context) {
    final theme = ShadTheme.of(context);
    final crop = _crop;
    final Widget child;
    if (_failed) {
      child = Text("Couldn't show this scan.", style: theme.textTheme.muted);
    } else if (crop == null) {
      child = const SizedBox.shrink();
    } else {
      child = Semantics(
        label: 'Scanned page. Tap to adjust its corners',
        button: true,
        excludeSemantics: true,
        onTap: _edit,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _edit,
          child: CornerBrackets(
            color: theme.colorScheme.primary,
            strokeWidth: 4,
            length: 0.14,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Image.memory(crop, gaplessPlayback: true),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(key: ValueKey(crop), child: child),
        ),
      ),
    );
  }
}

/// 64 dp round action: filled light for retake, outlined for confirm.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final background = filled ? colors.foreground : colors.background;
    final foreground = filled ? colors.background : colors.foreground;
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      onTap: onPressed,
      child: ShadIconButton(
        width: 64,
        height: 64,
        backgroundColor: background,
        hoverBackgroundColor: background,
        pressedBackgroundColor: filled ? colors.mutedForeground : colors.card,
        foregroundColor: foreground,
        hoverForegroundColor: foreground,
        decoration: ShadDecoration(
          shape: BoxShape.circle,
          border: ShadBorder.all(color: colors.foreground, width: 1.5),
        ),
        icon: Icon(icon, size: 24),
        onPressed: onPressed,
      ),
    );
  }
}
