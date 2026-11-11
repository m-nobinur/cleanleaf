import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../../capture/domain/scan_mode.dart';
import '../../capture/presentation/scan_mode_sheet.dart';

enum ShellTab { home, files }

/// Pill segmented control (Home / Files) and the round leaf scan FAB.
class FloatingNav extends StatelessWidget {
  const FloatingNav({
    super.key,
    required this.tab,
    required this.onTab,
    required this.quickScanMode,
    required this.onQuickScan,
    required this.onChooseMode,
  });

  final ShellTab tab;
  final ValueChanged<ShellTab> onTab;
  final ScanMode quickScanMode;
  final VoidCallback onQuickScan;
  final VoidCallback onChooseMode;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.nav,
            borderRadius: BorderRadius.circular(Radii.full),
            // The ink pill needs an edge only against the dark background.
            border: theme.brightness == Brightness.dark
                ? Border.all(color: colors.hairline)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Segment(
                icon: LucideIcons.house,
                label: 'Home',
                selected: tab == ShellTab.home,
                onTap: () => onTab(ShellTab.home),
              ),
              _Segment(
                icon: LucideIcons.folder,
                label: 'Files',
                selected: tab == ShellTab.files,
                onTap: () => onTab(ShellTab.files),
              ),
            ],
          ),
        ),
        const Spacer(),
        Semantics(
          label: 'Scan ${quickScanMode.label.toLowerCase()}',
          hint: 'Long press to choose a scan mode',
          button: true,
          excludeSemantics: true,
          onTap: onQuickScan,
          onLongPress: onChooseMode,
          child: ShadIconButton(
            key: const ValueKey('quick-scan'),
            width: 64,
            height: 64,
            backgroundColor: colors.primary,
            hoverBackgroundColor: colors.primary,
            pressedBackgroundColor: colors.primary,
            foregroundColor: colors.primaryForeground,
            hoverForegroundColor: colors.primaryForeground,
            decoration: ShadDecoration(
              shape: BoxShape.circle,
              shadows: colors.primaryGlow.a == 0
                  ? null
                  : [
                      BoxShadow(
                        color: colors.primaryGlow,
                        blurRadius: 28,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            icon: const Icon(LucideIcons.plus, size: 28),
            onPressed: onQuickScan,
            onLongPress: onChooseMode,
          ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.onNavSelected : colors.onNav;
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg + 2),
          decoration: BoxDecoration(
            color: selected ? colors.navSelected : colors.nav,
            borderRadius: BorderRadius.circular(Radii.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: Spacing.sm),
              Text(
                label,
                style: theme.textTheme.small.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
