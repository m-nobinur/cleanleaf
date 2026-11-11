import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/spacing.dart';
import '../../../core/widgets/bento_tile.dart';
import '../../../core/widgets/list_group.dart';
import '../../../core/widgets/modal_close_button.dart';
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
    barrierLabel: 'Dismiss',
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
    ListRow row(
      ConvertFormat format,
      IconData icon,
      TileTone tone,
      String label,
      String caption,
    ) => ListRow(
      key: ValueKey(format),
      icon: icon,
      tone: tone,
      title: label,
      caption: caption,
      onTap: () => Navigator.of(context).pop(format),
    );
    return ShadSheet(
      title: const ModalTitle('Convert'),
      // Keeps clear of the close button.
      description: Padding(
        padding: const EdgeInsets.only(right: Spacing.xl),
        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.lg),
        child: ListGroup(
          children: [
            row(
              ConvertFormat.pdf,
              LucideIcons.fileText,
              TileTone.ember,
              'PDF',
              'One file with every page',
            ),
            row(
              ConvertFormat.jpg,
              LucideIcons.image,
              TileTone.leaf,
              'JPG',
              'One image per page',
            ),
            row(
              ConvertFormat.png,
              LucideIcons.fileImage,
              TileTone.mist,
              'PNG',
              'Lossless, one image per page',
            ),
          ],
        ),
      ),
    );
  }
}
