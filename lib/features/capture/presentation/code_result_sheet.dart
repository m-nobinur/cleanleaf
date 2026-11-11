import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../domain/document_camera.dart';

/// Shows a decoded code (D-47): its type and text, with Copy, Share, Open for
/// web links and Scan again. Nothing is stored. Completes when it closes.
Future<void> showCodeResult(
  BuildContext context,
  ScannedCode code, {
  required Future<bool> Function(Uri link) openLink,
}) => showShadSheet<void>(
  context: context,
  side: ShadSheetSide.bottom,
  builder: (context) => _CodeResultSheet(code: code, openLink: openLink),
);

class _CodeResultSheet extends StatelessWidget {
  const _CodeResultSheet({required this.code, required this.openLink});

  // Three icon buttons share a phone's width.
  static const _actionPadding = EdgeInsets.symmetric(horizontal: Spacing.sm);

  final ScannedCode code;
  final Future<bool> Function(Uri link) openLink;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code.text));
    if (!context.mounted) return;
    ShadToaster.of(context).show(const ShadToast(title: Text('Copied')));
  }

  Future<void> _open(BuildContext context, Uri link) async {
    if (await openLink(link) || !context.mounted) return;
    ShadToaster.of(context).show(
      const ShadToast.destructive(title: Text('No app can open this link')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final link = code.webLink;
    return ShadSheet(
      radius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      removeBorderRadiusWhenTiny: false,
      title: Text(link != null ? 'Link' : 'Text'),
      description: Text(
        code.format.toUpperCase(),
        style: theme.textTheme.monoMeta.copyWith(color: colors.mutedForeground),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Spacing.md,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.3,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.muted,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: SelectableText(
                    code.text,
                    style: theme.textTheme.p.copyWith(color: colors.foreground),
                  ),
                ),
              ),
            ),
            Row(
              spacing: Spacing.sm,
              children: [
                Expanded(
                  child: ShadButton.outline(
                    padding: _actionPadding,
                    leading: const Icon(LucideIcons.copy, size: 18),
                    onPressed: () => _copy(context),
                    child: const Text('Copy'),
                  ),
                ),
                Expanded(
                  child: ShadButton.outline(
                    padding: _actionPadding,
                    leading: const Icon(LucideIcons.share2, size: 18),
                    onPressed: () =>
                        SharePlus.instance.share(ShareParams(text: code.text)),
                    child: const Text('Share'),
                  ),
                ),
                if (link != null)
                  Expanded(
                    child: ShadButton.outline(
                      padding: _actionPadding,
                      leading: const Icon(LucideIcons.externalLink, size: 18),
                      onPressed: () => _open(context, link),
                      child: const Text('Open'),
                    ),
                  ),
              ],
            ),
            ShadButton(
              leading: const Icon(LucideIcons.scanLine, size: 18),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Scan again'),
            ),
          ],
        ),
      ),
    );
  }
}
