import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../../library/domain/document.dart';
import '../data/export_providers.dart';
import '../domain/convert_format.dart';

/// Lets the user pick a format for [document], then shares it in that format.
Future<void> convertDocument(
  BuildContext context,
  WidgetRef ref,
  Document document, {
  Offset? toastOffset,
}) async {
  final format = await showShadSheet<ConvertFormat>(
    context: context,
    side: ShadSheetSide.bottom,
    builder: (_) => _ConvertSheet(title: document.title),
  );
  if (format == null || !context.mounted) return;
  await shareDocumentAs(
    context,
    ref,
    format,
    document.id,
    toastOffset: toastOffset,
  );
}

Future<void> shareDocumentAs(
  BuildContext context,
  WidgetRef ref,
  ConvertFormat format,
  String documentId, {
  Offset? toastOffset,
}) async {
  try {
    await switch (format) {
      ConvertFormat.pdf => ref.read(shareDocumentPdfProvider)(documentId),
      ConvertFormat.jpg => ref.read(shareDocumentJpgProvider)(documentId),
      ConvertFormat.png => ref.read(shareDocumentPngProvider)(documentId),
    };
  } on Object {
    if (!context.mounted) return;
    ShadToaster.of(context).show(
      ShadToast.destructive(
        offset: toastOffset,
        title: Text(switch (format) {
          ConvertFormat.pdf => 'Could not export this PDF',
          ConvertFormat.jpg ||
          ConvertFormat.png => 'Could not export the images',
        }),
      ),
    );
  }
}

class _ConvertSheet extends StatelessWidget {
  const _ConvertSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ShadSheet(
      radius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      removeBorderRadiusWhenTiny: false,
      title: const Text('Convert'),
      description: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      child: const Padding(
        padding: EdgeInsets.only(top: Spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FormatTile(
              format: ConvertFormat.pdf,
              icon: LucideIcons.fileText,
              label: 'PDF',
              caption: 'One file with every page',
            ),
            _FormatTile(
              format: ConvertFormat.jpg,
              icon: LucideIcons.image,
              label: 'JPG',
              caption: 'One image per page',
            ),
            _FormatTile(
              format: ConvertFormat.png,
              icon: LucideIcons.fileImage,
              label: 'PNG',
              caption: 'Lossless, one image per page',
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.format,
    required this.icon,
    required this.label,
    required this.caption,
  });

  final ConvertFormat format;
  final IconData icon;
  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return ShadButton.ghost(
      key: ValueKey(format),
      width: double.infinity,
      // 0 sizes the button to its two-line content.
      height: 0,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.md,
      ),
      expands: true,
      mainAxisAlignment: MainAxisAlignment.start,
      onPressed: () => Navigator.of(context).pop(format),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.foreground),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.p.copyWith(color: colors.foreground),
                ),
                Text(
                  caption,
                  style: theme.textTheme.muted.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
