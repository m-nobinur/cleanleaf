import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/round_icon_button.dart';
import '../../library/data/library_providers.dart';
import '../../library/domain/document_page.dart';
import '../data/enhance_providers.dart';
import '../domain/page_renderer.dart';
import 'adjust_panel.dart';

const _previewLongSide = 1600;
const _dragLongSide = 800;
const _chipLongSide = 400;
const _chipWidth = 72.0;
const _panelHeight = 132.0;
const _dragDebounce = Duration(milliseconds: 40);
// A tap on the track changes the value without an end event; this commits it.
const _settleDelay = Duration(milliseconds: 300);

enum _Mode { filters, adjust }

typedef _Draft = ({PageFilter filter, Map<Adjustment, double> adjustments});

// Unsaved filter and adjustments per page, kept while the user steps back to
// the corner editor, which rebuilds this screen when they return.
final _draftsProvider = Provider<Map<String, _Draft>>((ref) => {});

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
            final pageAsync = ref.watch(enhancePageProvider(pageId));
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
  late final _Draft? _draft = ref.read(_draftsProvider)[widget.page.id];
  late PageFilter _filter = _draft?.filter ?? widget.page.filter;
  late int _rotation = widget.page.rotation;
  late final Map<Adjustment, double> _adjustments =
      _draft?.adjustments ??
      {
        for (final a in Adjustment.values)
          a: widget.page.filterParams[a.name] ?? 0,
      };
  _Mode _mode = _Mode.filters;
  Adjustment _tool = Adjustment.brightness;
  late final _slider = ShadSliderController(initialValue: _adjustments[_tool]!);
  bool _comparing = false;
  bool _saving = false;
  // One render per (filter, size, adjusted) at the current rotation and
  // adjustments; cleared when either changes.
  final _renders = <(PageFilter, int, bool), Future<Uint8List>>{};
  // While a slider moves: the latest small render, one at a time, latest wins.
  Future<Uint8List>? _dragPreview;
  bool _dragBusy = false;
  bool _dragPending = false;
  Timer? _dragTimer;
  Timer? _settleTimer;
  late final Future<String> _originalPath = ref
      .read(fileStoreProvider)
      .resolve(widget.page.originalPath)
      .then((file) => file.path);

  @override
  void dispose() {
    _dragTimer?.cancel();
    _settleTimer?.cancel();
    _slider.dispose();
    super.dispose();
  }

  Map<String, double> _params(
    Map<String, double> base, {
    bool adjusted = true,
  }) => {
    for (final e in base.entries)
      if (!Adjustment.values.any((a) => a.name == e.key)) e.key: e.value,
    if (adjusted)
      for (final e in _adjustments.entries)
        if (e.value != 0) e.key.name: e.value,
  };

  Future<Uint8List> _renderNow(
    PageFilter filter,
    int longSide, {
    bool adjusted = true,
  }) async => ref
      .read(pageRendererProvider)
      .render(
        await _originalPath,
        widget.page.corners,
        _rotation,
        filter,
        _params(widget.page.filterParams, adjusted: adjusted),
        maxLongSide: longSide,
      );

  Future<Uint8List> _render(
    PageFilter filter,
    int longSide, {
    bool adjusted = true,
  }) => _renders.putIfAbsent((
    filter,
    longSide,
    adjusted,
  ), () => _renderNow(filter, longSide, adjusted: adjusted));

  void _renderDrag() {
    if (_dragBusy) {
      _dragPending = true;
      return;
    }
    _dragBusy = true;
    final future = _renderNow(_filter, _dragLongSide);
    setState(() {
      _dragPreview = future;
    });
    future.whenComplete(() {
      _dragBusy = false;
      if (_dragPending && mounted) {
        _dragPending = false;
        _renderDrag();
      }
    }).ignore();
  }

  void _onAdjust(double value) {
    setState(() => _adjustments[_tool] = value);
    _dragTimer?.cancel();
    _dragTimer = Timer(_dragDebounce, _renderDrag);
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, () => _commitAdjust(_tool, value));
  }

  // Shows the full-size preview of the adjustments as they now stand.
  void _commitAdjust(Adjustment tool, double value) {
    _dragTimer?.cancel();
    _settleTimer?.cancel();
    _dragPending = false;
    if (tool == _tool) _slider.value = value;
    setState(() {
      _adjustments[tool] = value;
      _dragPreview = null;
      _renders.clear();
    });
  }

  void _selectTool(Adjustment tool) => setState(() {
    _tool = tool;
    _slider.value = _adjustments[tool]!;
  });

  void _resetAll() {
    for (final a in Adjustment.values) {
      _commitAdjust(a, 0);
    }
  }

  bool get _adjusted => _adjustments.values.any((v) => v != 0);

  void _backToCrop() {
    ref.read(_draftsProvider)[widget.page.id] = (
      filter: _filter,
      adjustments: Map.of(_adjustments),
    );
    context.canPop()
        ? context.pop()
        : context.go(AppRoutes.editor(widget.page.id));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(pageRepositoryProvider);
      final renderer = ref.read(pageRendererProvider);
      // Re-read: the stored page may have changed since this screen opened.
      final page = await repo.get(widget.page.id) ?? widget.page;
      final params = _params(page.filterParams);
      final render = await renderer.render(
        await _originalPath,
        page.corners,
        _rotation,
        _filter,
        params,
      );
      final thumb = await renderer.thumbnail(render);
      await repo.saveRender(
        page.id,
        render: Stream.value(render),
        thumb: Stream.value(thumb),
      );
      await repo.updateEdits(
        page.copyWith(
          filter: _filter,
          rotation: _rotation,
          filterParams: params,
        ),
      );
      ref.read(_draftsProvider).remove(page.id);
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
    final adjusting = _mode == _Mode.adjust;
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
              if (adjusting && _adjusted)
                Align(
                  alignment: Alignment.centerRight,
                  child: ShadButton.ghost(
                    foregroundColor: theme.colorScheme.foreground,
                    onPressed: _saving ? null : _resetAll,
                    child: const Text('Reset'),
                  ),
                ),
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
              child: _Preview(
                future: _comparing
                    ? _render(shown, _previewLongSide, adjusted: false)
                    : _dragPreview ?? _render(shown, _previewLongSide),
                // Slider updates swap in place; a dimmed flash per step would flicker.
                showLoading: !adjusting,
              ),
            ),
          ),
        ),
        Text(
          _comparing ? 'Original' : 'Hold the page to compare',
          textAlign: TextAlign.center,
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: Spacing.md),
        Center(
          child: _ModeSwitch(
            mode: _mode,
            onChanged: (mode) => setState(() => _mode = mode),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        SizedBox(
          height: _panelHeight,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            child: adjusting
                ? Center(
                    key: const ValueKey(_Mode.adjust),
                    child: AdjustPanel(
                      values: _adjustments,
                      filter: _filter,
                      tool: _tool,
                      controller: _slider,
                      onTool: _selectTool,
                      onChanged: _onAdjust,
                      onChangeEnd: (v) => _commitAdjust(_tool, v),
                      onReset: () => _commitAdjust(_tool, 0),
                      onPerspective: _saving ? () {} : _backToCrop,
                    ),
                  )
                : ListView(
                    key: const ValueKey(_Mode.filters),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg,
                      vertical: Spacing.sm,
                    ),
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
        ),
        Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Row(
            spacing: Spacing.md,
            children: [
              RoundIconButton(
                icon: LucideIcons.rotateCw,
                label: 'Rotate',
                onPressed: () {
                  if (_saving) return;
                  setState(() {
                    _rotation = (_rotation + 90) % 360;
                    _dragPreview = null;
                    _renders.clear();
                  });
                },
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

/// FILTERS / ADJUST pill, in the camera's mode-pill style.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final _Mode mode;
  final ValueChanged<_Mode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
      decoration: BoxDecoration(
        color: colors.nav,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (m, label) in [
            (_Mode.filters, 'Filters'),
            (_Mode.adjust, 'Adjust'),
          ])
            Semantics(
              label: label,
              button: true,
              selected: m == mode,
              excludeSemantics: true,
              onTap: () => onChanged(m),
              // The pill is 40 dp; the padding brings each target to 48 dp.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: 40,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                    decoration: BoxDecoration(
                      color: m == mode ? colors.navSelected : colors.nav,
                      borderRadius: BorderRadius.circular(Radii.full),
                    ),
                    child: Text(
                      label.toUpperCase(),
                      style: theme.textTheme.monoLabel.copyWith(
                        color: m == mode ? colors.onNavSelected : colors.onNav,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Preview extends StatefulWidget {
  const _Preview({required this.future, this.showLoading = true});

  final Future<Uint8List> future;
  final bool showLoading;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  Uint8List? _bytes;
  Future<Uint8List>? _shown;
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
        if (mounted && future == widget.future) {
          setState(() {
            _bytes = bytes;
            _shown = future;
          });
        }
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
    const spinner = Center(
      child: SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
    final bytes = _bytes;
    if (bytes == null) return spinner;
    final loading = widget.showLoading && _shown != widget.future;
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: loading ? 0.5 : 1,
          child: Image.memory(
            bytes,
            gaplessPlayback: true,
            fit: BoxFit.contain,
            semanticLabel: 'Page preview',
          ),
        ),
        if (loading) spinner,
      ],
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
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(
                    color: selected ? colors.primary : colors.hairline,
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
