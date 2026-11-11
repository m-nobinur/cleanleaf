import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import '../theme/spacing.dart';
import '../widgets/corner_brackets.dart';
import '../widgets/list_group.dart';
import '../widgets/modal_close_button.dart';

/// Keep in sync with `version:` in pubspec.yaml (checked by the licenses test).
const appVersion = '0.1.0';

Future<void> showAboutSheet(BuildContext context) => showShadSheet<void>(
  context: context,
  barrierLabel: 'Dismiss',
  side: ShadSheetSide.bottom,
  builder: (_) => const AboutSheet(),
);

class AboutSheet extends StatelessWidget {
  const AboutSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return ShadSheet(
      title: const ModalTitle('About'),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const BrandBadge(size: 56),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cleanleaf',
                        style: theme.textTheme.tileTitle.copyWith(
                          color: colors.foreground,
                        ),
                      ),
                      Text(
                        'Version $appVersion',
                        style: theme.textTheme.monoMeta.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'A document scanner that works offline. '
              'No account, no ads, no tracking.',
              style: theme.textTheme.muted.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            ListGroup(
              children: [
                ListRow(
                  icon: LucideIcons.scale,
                  title: 'Open source licenses',
                  caption: 'Libraries and models Cleanleaf uses',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Cleanleaf',
                    applicationVersion: appVersion,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
