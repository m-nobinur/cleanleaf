import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/spacing.dart';

/// Keep in sync with `version:` in pubspec.yaml (checked by the licenses test).
const appVersion = '0.1.0';

Future<void> showAboutSheet(BuildContext context) => showShadSheet<void>(
  context: context,
  side: ShadSheetSide.bottom,
  builder: (_) => const AboutSheet(),
);

class AboutSheet extends StatelessWidget {
  const AboutSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadSheet(
      title: const Text('About'),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cleanleaf', style: theme.textTheme.h4),
            Text('Version $appVersion', style: theme.textTheme.muted),
            const SizedBox(height: Spacing.lg),
            ShadButton.outline(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Cleanleaf',
                applicationVersion: appVersion,
              ),
              child: const Text('Open source licenses'),
            ),
          ],
        ),
      ),
    );
  }
}
