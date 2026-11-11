import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/licenses/about_sheet.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/bento_tile.dart';
import '../../../core/widgets/list_group.dart';
import '../../../core/widgets/modal_close_button.dart';
import '../../scan_engine/presentation/scan_engine_dialog.dart';

class SettingsRow {
  const SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = TileTone.mist,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final TileTone tone;
  final void Function(BuildContext context)? onTap;
}

/// Append a row here to add a settings entry.
const settingsRows = <SettingsRow>[
  SettingsRow(
    icon: LucideIcons.lock,
    title: 'Private by design',
    subtitle: 'Your scans stay on this device.',
    tone: TileTone.leaf,
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
  barrierLabel: 'Dismiss',
  side: ShadSheetSide.bottom,
  builder: (_) => const SettingsSheet(),
);

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, this.rows = settingsRows});

  final List<SettingsRow> rows;

  @override
  Widget build(BuildContext context) {
    return ShadSheet(
      title: const ModalTitle('Settings'),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.lg),
        child: ListGroup(
          children: [
            for (final row in rows)
              ListRow(
                icon: row.icon,
                tone: row.tone,
                title: row.title,
                caption: row.subtitle,
                onTap: row.onTap == null ? null : () => row.onTap!(context),
              ),
          ],
        ),
      ),
    );
  }
}
