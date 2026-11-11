import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/licenses/about_sheet.dart';
import '../../../core/theme/spacing.dart';
import '../../scan_engine/presentation/scan_engine_dialog.dart';

class SettingsRow {
  const SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final void Function(BuildContext context)? onTap;
}

/// Append a row here to add a settings entry.
const settingsRows = <SettingsRow>[
  SettingsRow(
    icon: LucideIcons.lock,
    title: 'Private by design',
    subtitle: 'Your scans stay on this device.',
  ),
  SettingsRow(
    icon: LucideIcons.scanLine,
    title: 'Scanner engine',
    subtitle: 'Cleanleaf or Google ML Kit',
    onTap: showScanEngineDialog,
  ),
  SettingsRow(
    icon: LucideIcons.info,
    title: 'About & licenses',
    onTap: showAboutSheet,
  ),
];

Future<void> showSettingsSheet(BuildContext context) => showShadSheet<void>(
  context: context,
  side: ShadSheetSide.bottom,
  builder: (_) => const SettingsSheet(),
);

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, this.rows = settingsRows});

  final List<SettingsRow> rows;

  @override
  Widget build(BuildContext context) {
    return ShadSheet(
      title: const Text('Settings'),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final row in rows) _SettingsTile(row: row)],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.row});

  final SettingsRow row;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final onTap = row.onTap;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(row.title, style: theme.textTheme.p),
        if (row.subtitle != null)
          Text(row.subtitle!, style: theme.textTheme.muted),
      ],
    );
    final content = Row(
      children: [
        Icon(row.icon, size: 20),
        const SizedBox(width: Spacing.md),
        Expanded(child: text),
      ],
    );
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: content,
      );
    }
    return ShadButton.ghost(
      width: double.infinity,
      // 0 sizes the button to its two-line content.
      height: 0,
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      expands: true,
      mainAxisAlignment: MainAxisAlignment.start,
      onPressed: () => onTap(context),
      child: content,
    );
  }
}
