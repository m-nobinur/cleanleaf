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

/// The scan modes the camera can switch between, as a mono segmented pill.
class ModeSwitch extends StatelessWidget {
  const ModeSwitch({super.key, required this.mode, required this.onChanged});

  final ScanMode mode;
  final ValueChanged<ScanMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.xs),
      decoration: BoxDecoration(
        color: colors.nav,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in ScanMode.values.where((m) => m.isAvailable))
            Semantics(
              label: '${m.label} mode',
              button: true,
              selected: m == mode,
              excludeSemantics: true,
              onTap: () => onChanged(m),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  height: 40,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  decoration: BoxDecoration(
                    color: m == mode ? colors.navSelected : colors.nav,
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                  child: Text(
                    m.label.toUpperCase(),
                    style: theme.textTheme.monoLabel.copyWith(
                      color: m == mode ? colors.onNavSelected : colors.onNav,
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

/// "AUTO" pill; the ember dot marks auto-capture as on.
class AutoCaptureToggle extends StatelessWidget {
  const AutoCaptureToggle({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      label: 'Auto-capture',
      toggled: enabled,
      button: true,
      excludeSemantics: true,
      onTap: () => onChanged(!enabled),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!enabled),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(Radii.full),
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: enabled ? colors.highlight : colors.mutedForeground,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                'AUTO',
                style: theme.textTheme.monoLabel.copyWith(
                  color: enabled ? colors.foreground : colors.mutedForeground,
                ),
              ),
            ],
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
              style: theme.textTheme.muted,
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
