import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/corner_brackets.dart';
import '../domain/scan_mode.dart';
import 'scan_mode_sheet.dart';

/// Round ink shutter with a light ring, the same in light and dark frames.
class ShutterButton extends StatelessWidget {
  const ShutterButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ink = AppTheme.dark.colorScheme;
    return Semantics(
      label: 'Take photo',
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      onTap: onPressed,
      child: AnimatedOpacity(
        opacity: onPressed == null ? 0.5 : 1,
        duration: const Duration(milliseconds: 150),
        child: ShadIconButton(
          width: 76,
          height: 76,
          backgroundColor: ink.background,
          hoverBackgroundColor: ink.card,
          pressedBackgroundColor: ink.card,
          foregroundColor: ink.foreground,
          hoverForegroundColor: ink.foreground,
          decoration: ShadDecoration(
            shape: BoxShape.circle,
            border: ShadBorder.all(color: ink.foreground, width: 4),
          ),
          icon: const Icon(LucideIcons.camera, size: 28),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// "Hold still" with a pulsing ember dot, shown while auto-capture arms.
class HoldStillPill extends StatelessWidget {
  const HoldStillPill({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(Radii.full),
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.highlight,
                    shape: BoxShape.circle,
                  ),
                )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fade(begin: 1, end: 0.3, duration: 600.ms)
                .scaleXY(begin: 1, end: 0.75, duration: 600.ms),
            const SizedBox(width: Spacing.sm),
            Text(
              'Hold still',
              style: theme.textTheme.small.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every scan mode as a horizontally scrolling pill row. The selected pill
/// scrolls into view.
class ModePills extends StatefulWidget {
  const ModePills({super.key, required this.mode, required this.onChanged});

  final ScanMode mode;
  final ValueChanged<ScanMode> onChanged;

  @override
  State<ModePills> createState() => _ModePillsState();
}

class _ModePillsState extends State<ModePills> {
  final _keys = {for (final m in ScanMode.values) m: GlobalKey()};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(Duration.zero));
  }

  @override
  void didUpdateWidget(ModePills old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) {
      _reveal(const Duration(milliseconds: 250));
    }
  }

  void _reveal(Duration duration) {
    final context = _keys[widget.mode]!.currentContext;
    if (context == null || !mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: duration,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only the mask's alpha matters; the colour is any opaque token.
    final opaque = ShadTheme.of(context).colorScheme.foreground;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final fade = _fade / rect.width;
        return LinearGradient(
          colors: [
            opaque.withValues(alpha: 0),
            opaque,
            opaque,
            opaque.withValues(alpha: 0),
          ],
          stops: [0, fade, 1 - fade, 1],
        ).createShader(rect);
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _fade),
        child: Row(
          children: [
            for (final m in ScanMode.values)
              _ModePill(
                key: _keys[m],
                mode: m,
                selected: m == widget.mode,
                onTap: () => widget.onChanged(m),
              ),
          ],
        ),
      ),
    );
  }

  static const _fade = Spacing.xl;
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    super.key,
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ScanMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final label = theme.textTheme.monoLabel;
    return Semantics(
      label: '${mode.label} mode',
      button: true,
      selected: selected,
      excludeSemantics: true,
      onTap: onTap,
      // The pill is 40 dp; the padding brings each target to 48 dp.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xs / 2,
            vertical: Spacing.xs,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 40,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            decoration: BoxDecoration(
              color: selected ? colors.navSelected : colors.nav,
              borderRadius: BorderRadius.circular(Radii.full),
            ),
            child: Text(
              mode.label.toUpperCase(),
              style: label.copyWith(
                color: selected ? colors.onNavSelected : colors.onNav,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The auto-capture chip, in the mode pills' shape: solid leaf with an ember
/// dot when on (pulsing while a shot arms), graphite with a hollow ring when
/// off. A toggle ticks and briefly reads "Auto: on" or "Auto: off".
class AutoCaptureToggle extends StatefulWidget {
  const AutoCaptureToggle({
    super.key,
    required this.enabled,
    required this.onChanged,
    this.arming = false,
  });

  final bool enabled;
  final bool arming;
  final ValueChanged<bool> onChanged;

  @override
  State<AutoCaptureToggle> createState() => _AutoCaptureToggleState();
}

class _AutoCaptureToggleState extends State<AutoCaptureToggle> {
  Timer? _announce;

  @override
  void dispose() {
    _announce?.cancel();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    _announce?.cancel();
    _announce = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _announce = null);
    });
    widget.onChanged(!widget.enabled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final on = widget.enabled;
    final text = _announce == null ? 'AUTO' : (on ? 'AUTO: ON' : 'AUTO: OFF');
    final ink = on ? colors.primaryForeground : colors.onNav;
    Widget dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? colors.highlight : null,
        border: on ? null : Border.all(color: ink, width: 1.5),
      ),
    );
    if (on && widget.arming) {
      dot = dot
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .fade(begin: 1, end: 0.3, duration: 600.ms)
          .scaleXY(begin: 1, end: 0.75, duration: 600.ms);
    }
    return Semantics(
      label: 'Auto-capture',
      toggled: on,
      button: true,
      excludeSemantics: true,
      onTap: _toggle,
      // The pill is 40 dp, like the mode pills; the padding makes 48 dp.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 40,
            constraints: const BoxConstraints(minWidth: 84),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            decoration: BoxDecoration(
              color: on ? colors.primary : colors.nav,
              borderRadius: BorderRadius.circular(Radii.full),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                dot,
                const SizedBox(width: Spacing.sm),
                AnimatedSize(
                  duration: const Duration(milliseconds: 150),
                  child: Text(
                    text,
                    style: theme.textTheme.monoLabel.copyWith(color: ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon over a text label, for the import shortcut beside the shutter.
class LabeledIconButton extends StatelessWidget {
  const LabeledIconButton({
    super.key,
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
    final color = theme.colorScheme.foreground;
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 72,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: Spacing.xs),
              Text(label, style: theme.textTheme.small.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A centred notice with the bracket motif, for permission and failure states.
class CameraNotice extends StatelessWidget {
  const CameraNotice({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.secondary,
  });

  final String title;
  final String message;
  final Widget? action;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 72,
              child: CornerBrackets(
                color: colors.primary,
                strokeWidth: 3,
                child: Icon(
                  LucideIcons.camera,
                  size: 28,
                  color: colors.foreground,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.tileTitle.copyWith(
                color: colors.foreground,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              // muted has no colour, so it would inherit the app's ink text colour.
              style: theme.textTheme.muted.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: Spacing.xl),
              action!,
            ],
            if (secondary != null) ...[
              const SizedBox(height: Spacing.sm),
              secondary!,
            ],
          ],
        ),
      ),
    );
  }
}
