import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../library/domain/document_page.dart';
import '../domain/page_renderer.dart';

const _icons = {
  Adjustment.brightness: LucideIcons.sun,
  Adjustment.contrast: LucideIcons.contrast,
  Adjustment.saturation: LucideIcons.droplet,
  Adjustment.sharpness: LucideIcons.focus,
  Adjustment.straighten: LucideIcons.ruler,
};

const _filterNames = {
  PageFilter.grayscale: 'Grayscale',
  PageFilter.blackWhite: 'B&W',
};

const _thumbRadius = 11.0;
// The slider's own track is the whole 48 dp touch target; the visible track
// is painted behind it.
const _sliderHeight = 48.0;

String adjustmentLabel(Adjustment a) =>
    '${a.name[0].toUpperCase()}${a.name.substring(1)}';

/// Signed readout: -100..100 for tone and sharpness, degrees for straighten.
String formatAdjustment(Adjustment a, double value) {
  final sign = value > 0
      ? '+'
      : value < 0
      ? '−'
      : '';
  return a == Adjustment.straighten
      ? '$sign${value.abs().toStringAsFixed(1)}°'
      : '$sign${(value.abs() * 100).round()}';
}

/// One slider for the selected [Adjustment] above a row of tools, plus the
/// entry to the corner editor for perspective.
class AdjustPanel extends StatelessWidget {
  const AdjustPanel({
    super.key,
    required this.values,
    required this.filter,
    required this.tool,
    required this.controller,
    required this.onTool,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
    required this.onPerspective,
  });

  final Map<Adjustment, double> values;
  final PageFilter filter;
  final Adjustment tool;
  final ShadSliderController controller;
  final ValueChanged<Adjustment> onTool;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback onReset;
  final VoidCallback onPerspective;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final value = values[tool] ?? 0;
    final enabled = tool.appliesTo(filter);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Text(
                  adjustmentLabel(tool).toUpperCase(),
                  style: theme.textTheme.monoLabel.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
                const Spacer(),
                if (!enabled)
                  Text(
                    'No effect on ${_filterNames[filter]}',
                    style: theme.textTheme.monoMeta.copyWith(
                      color: colors.mutedForeground,
                    ),
                  )
                else ...[
                  Text(
                    formatAdjustment(tool, value),
                    style: theme.textTheme.monoMeta.copyWith(
                      color: colors.foreground,
                    ),
                  ),
                  // Kept in the layout at 0 so the readout doesn't shift.
                  Opacity(
                    opacity: value == 0 ? 0 : 1,
                    child: ShadIconButton.ghost(
                      width: 32,
                      height: 32,
                      foregroundColor: colors.mutedForeground,
                      icon: const Icon(LucideIcons.rotateCcw, size: 16),
                      onPressed: value == 0 ? null : onReset,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _CentredSlider(
            key: ValueKey(tool),
            label: adjustmentLabel(tool),
            limit: tool.limit,
            enabled: enabled,
            controller: controller,
            format: (v) => formatAdjustment(tool, v),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
          const SizedBox(height: Spacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final a in Adjustment.values)
                _ToolButton(
                  icon: _icons[a]!,
                  label: adjustmentLabel(a),
                  selected: a == tool,
                  changed: (values[a] ?? 0) != 0,
                  enabled: a.appliesTo(filter),
                  onTap: () => onTool(a),
                ),
              Container(width: 1, height: 28, color: colors.hairline),
              _ToolButton(
                icon: LucideIcons.scan,
                label: 'Perspective',
                hint: 'Opens the corner editor',
                selected: false,
                changed: false,
                enabled: true,
                onTap: onPerspective,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A slider centred on 0: the fill runs from the centre tick to the thumb.
class _CentredSlider extends StatelessWidget {
  const _CentredSlider({
    super.key,
    required this.label,
    required this.limit,
    required this.enabled,
    required this.controller,
    required this.format,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double limit;
  final bool enabled;
  final ShadSliderController controller;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    const transparent = Color(0x00000000);
    return Semantics(
      label: label,
      child: Padding(
        // The thumb overhangs both ends of the track by its radius.
        padding: const EdgeInsets.symmetric(horizontal: _thumbRadius),
        child: SizedBox(
          height: _sliderHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (context, value, _) => CustomPaint(
                    painter: _TrackPainter(
                      fraction: value / limit,
                      track: colors.muted,
                      fill: enabled ? colors.primary : colors.muted,
                      tick: colors.mutedForeground,
                    ),
                  ),
                ),
              ),
              ShadSlider(
                controller: controller,
                min: -limit,
                max: limit,
                enabled: enabled,
                trackHeight: _sliderHeight,
                thumbRadius: _thumbRadius,
                activeTrackColor: transparent,
                inactiveTrackColor: transparent,
                disabledActiveTrackColor: transparent,
                disabledInactiveTrackColor: transparent,
                thumbColor: colors.foreground,
                thumbBorderColor: colors.foreground,
                disabledThumbColor: colors.muted,
                disabledThumbBorderColor: colors.muted,
                semanticFormatterCallback: format,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  const _TrackPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.tick,
  });

  /// -1..1, the thumb's offset from the centre.
  final double fraction;
  final Color track;
  final Color fill;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    const height = 4.0;
    final y = size.height / 2, centre = size.width / 2;
    final paint = Paint()
      ..strokeWidth = height
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset(0, y), Offset(size.width, y), paint..color = track)
      ..drawLine(
        Offset(centre, y),
        Offset(centre + fraction.clamp(-1, 1) * centre, y),
        paint..color = fill,
      )
      ..drawLine(
        Offset(centre, y - 7),
        Offset(centre, y + 7),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = tick,
      );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.fill != fill ||
      old.tick != tick;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.changed,
    required this.enabled,
    required this.onTap,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final bool selected;
  final bool changed;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Semantics(
      label: [
        label,
        if (changed) 'adjusted',
        if (!enabled) 'no effect on this filter',
      ].join(', '),
      hint: hint,
      button: true,
      selected: selected,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? colors.navSelected : colors.card,
                  border: Border.all(
                    color: selected ? colors.navSelected : colors.hairline,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: selected ? colors.onNavSelected : colors.foreground,
                ),
              ),
              if (changed)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.highlight,
                      border: Border.all(color: colors.background),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
