import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../editor/presentation/editor_providers.dart';
import '../../library/data/library_providers.dart';
import '../../library/domain/document_page.dart';
import '../data/enhance_providers.dart';

const _previewLongSide = 1600;
const _chipLongSide = 400;
const _chipWidth = 72.0;

const _filterLabels = {
  PageFilter.original: 'Original',
  PageFilter.enhancedColor: 'Enhanced',
  PageFilter.grayscale: 'Grayscale',
  PageFilter.blackWhite: 'B&W',
};

class EnhanceScreen extends ConsumerWidget {
  const EnhanceScreen({super.key, required this.pageId});

  final String pageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Dark (ink) in both app themes, like the crop editor.
    return ShadTheme(
      data: AppTheme.dark,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Builder(
          builder: (context) {
            final theme = ShadTheme.of(context);
            final pageAsync = ref.watch(editorPageProvider(pageId));
            return Scaffold(
              backgroundColor: theme.colorScheme.background,
              body: DefaultTextStyle.merge(
                style: TextStyle(color: theme.colorScheme.foreground),
                child: SafeArea(
                  child: pageAsync.when(
                    data: (page) => _Enhance(page: page),
                    error: (_, _) => Center(
                      child: Text(
                        "Couldn't open this page.",
                        style: theme.textTheme.muted,
                      ),
                    ),
                    loading: () => const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Enhance extends ConsumerStatefulWidget {
  const _Enhance({required this.page});

  final DocumentPage page;

  @override
  ConsumerState<_Enhance> createState() => _EnhanceState();
}

class _EnhanceState extends ConsumerState<_Enhance> {
  late PageFilter _filter = widget.page.filter;
  late int _rotation = widget.page.rotation;
  bool _comparing = false;
  bool _saving = false;
  // One render per (filter, size) at the current rotation; cleared on rotate.
  final _renders = <(PageFilter, int), Future<Uint8List>>{};
  late final Future<String> _originalPath = ref
      .read(fileStoreProvider)
      .resolve(widget.page.originalPath)
      .then((file) => file.path);

  Future<Uint8List> _render(PageFilter filter, int longSide) =>
      _renders.putIfAbsent((filter, longSide), () async {
        final page = widget.page;
        return ref
            .read(pageRendererProvider)
            .render(
              await _originalPath,
              page.corners,
              _rotation,
              filter,
              page.filterParams,
              maxLongSide: longSide,
            );
      });

  void _backToCrop() => context.canPop()
      ? context.pop()
      : context.go(AppRoutes.editor(widget.page.id));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(pageRepositoryProvider);
      final renderer = ref.read(pageRendererProvider);
      // Re-read: the stored page may have changed since this screen opened.
      final page = await repo.get(widget.page.id) ?? widget.page;
      final render = await renderer.render(
        await _originalPath,
        page.corners,
        _rotation,
        _filter,
        page.filterParams,
      );
      final thumb = await renderer.thumbnail(render);
      await repo.saveRender(
        page.id,
        render: Stream.value(render),
        thumb: Stream.value(thumb),
      );
      await repo.updateEdits(
        page.copyWith(filter: _filter, rotation: _rotation),
      );
      if (mounted) context.go(AppRoutes.library);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ShadToaster.of(context).show(
          const ShadToast.destructive(title: Text("Couldn't save the page")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final shown = _comparing ? PageFilter.original : _filter;
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
                  onPressed: _saving ? null : _backToCrop,
                  leading: const Icon(LucideIcons.arrowLeft),
                  child: const Text('Crop'),
                ),
              ),
              Text('Enhance', style: theme.textTheme.h4),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => setState(() => _comparing = true),
            onLongPressEnd: (_) => setState(() => _comparing = false),
            onLongPressCancel: () => setState(() => _comparing = false),
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: _Preview(future: _render(shown, _previewLongSide)),
            ),
          ),
        ),
        Text(
          _comparing ? 'Original' : 'Hold the page to compare',
          textAlign: TextAlign.center,
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: Spacing.md),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            children: [
              for (final filter in PageFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: Spacing.md),
                  child: _FilterChip(
                    label: _filterLabels[filter]!,
                    selected: filter == _filter,
                    thumb: _render(filter, _chipLongSide),
                    onTap: () => setState(() => _filter = filter),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Row(
            spacing: Spacing.md,
            children: [
              ShadIconButton.outline(
                width: kMinInteractiveDimension,
                height: kMinInteractiveDimension,
                icon: const Icon(LucideIcons.rotateCw),
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _rotation = (_rotation + 90) % 360;
                        _renders.clear();
                      }),
              ),
              Expanded(
                child: ShadButton(
                  size: ShadButtonSize.lg,
                  enabled: !_saving,
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Preview extends StatefulWidget {
  const _Preview({required this.future});

  final Future<Uint8List> future;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  Uint8List? _bytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Preview old) {
    super.didUpdateWidget(old);
    if (old.future != widget.future) _load();
  }

  void _load() {
    final future = widget.future;
    _error = null;
    future.then(
      (bytes) {
        if (mounted && future == widget.future) setState(() => _bytes = bytes);
      },
      onError: (Object error) {
        if (mounted && future == widget.future) setState(() => _error = error);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (_error != null) {
      return Center(
        child: Text("Couldn't render this page.", style: theme.textTheme.muted),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Image.memory(
      bytes,
      gaplessPlayback: true,
      fit: BoxFit.contain,
      semanticLabel: 'Page preview',
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.thumb,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Future<Uint8List> thumb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _chipWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 80,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: theme.radius,
                  border: Border.all(
                    color: selected ? colors.primary : colors.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: FutureBuilder(
                  future: thumb,
                  builder: (context, snapshot) => snapshot.hasData
                      ? Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.small.copyWith(
                  color: selected ? colors.foreground : colors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
