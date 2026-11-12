import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/spacing.dart';
import '../../../core/widgets/bento_tile.dart';
import '../../../core/widgets/list_group.dart';
import '../../../core/widgets/modal_close_button.dart';
import '../../library/data/library_providers.dart';
import '../../library/domain/document.dart';
import '../../library/domain/document_page.dart';
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
    if (_readsText(format)) {
      await _toastWhileReading(context, ref, documentId, toastOffset);
    }
    await switch (format) {
      ConvertFormat.pdf => ref.read(shareDocumentPdfProvider)(documentId),
      ConvertFormat.jpg => ref.read(shareDocumentJpgProvider)(documentId),
      ConvertFormat.png => ref.read(shareDocumentPngProvider)(documentId),
      ConvertFormat.searchablePdf => ref.read(
        shareDocumentSearchablePdfProvider,
      )(documentId),
      ConvertFormat.docx => ref.read(shareDocumentDocxProvider)(documentId),
      ConvertFormat.txt => ref.read(shareDocumentTxtProvider)(documentId),
    };
  } on Object {
    if (!context.mounted) return;
    ShadToaster.of(context).show(
      ShadToast.destructive(
        offset: toastOffset,
        title: Text(switch (format) {
          ConvertFormat.pdf ||
          ConvertFormat.searchablePdf => 'Could not export this PDF',
          ConvertFormat.jpg ||
          ConvertFormat.png => 'Could not export the images',
          ConvertFormat.docx ||
          ConvertFormat.txt => 'Could not export the text',
        }),
      ),
    );
  }
}

bool _readsText(ConvertFormat format) => switch (format) {
  ConvertFormat.searchablePdf ||
  ConvertFormat.docx ||
  ConvertFormat.txt => true,
  ConvertFormat.pdf || ConvertFormat.jpg || ConvertFormat.png => false,
};

/// Unread pages take seconds each, so say why the share sheet is slow.
Future<void> _toastWhileReading(
  BuildContext context,
  WidgetRef ref,
  String documentId,
  Offset? toastOffset,
) async {
  final pages = await ref
      .read(pageRepositoryProvider)
      .getByDocument(documentId);
  if (!context.mounted ||
      pages.every((page) => page.ocrStatus == OcrStatus.done)) {
    return;
  }
  ShadToaster.of(context).show(
    ShadToast(
      offset: toastOffset,
      title: const Text('Reading text…'),
      description: const Text('This takes a few seconds per page.'),
    ),
  );
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
            row(
              ConvertFormat.searchablePdf,
              LucideIcons.fileSearch,
              TileTone.ember,
              'Searchable PDF',
              'PDF with selectable, searchable text',
            ),
            row(
              ConvertFormat.docx,
              LucideIcons.fileType,
              TileTone.leaf,
              'Word',
              'Editable .docx, one paragraph per text block',
            ),
            row(
              ConvertFormat.txt,
              LucideIcons.scanText,
              TileTone.mist,
              'Text',
              'Plain .txt with all the text',
            ),
          ],
        ),
      ),
    );
  }
}
