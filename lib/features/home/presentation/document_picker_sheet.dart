import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/list_group.dart';
import '../../../core/widgets/modal_close_button.dart';
import '../../library/domain/document.dart';
import '../../library/presentation/document_card.dart';
import '../../library/presentation/library_providers.dart';

Future<Document?> showDocumentPicker(
  BuildContext context,
  List<Document> documents, {
  required String title,
  required String description,
}) => showShadSheet<Document>(
  context: context,
  barrierLabel: 'Dismiss',
  side: ShadSheetSide.bottom,
  builder: (context) => ShadSheet(
    title: ModalTitle(title),
    description: Text(description),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.55,
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.lg),
        child: ListGroup.builder(
          itemCount: documents.length,
          itemBuilder: (context, i) => _DocumentRow(
            key: ValueKey(documents[i].id),
            document: documents[i],
            onTap: () => Navigator.of(context).pop(documents[i]),
          ),
        ),
      ),
    ),
  ),
);

class _DocumentRow extends ConsumerWidget {
  const _DocumentRow({super.key, required this.document, required this.onTap});

  final Document document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(documentPagesProvider(document.id)).value;
    final count = pages?.length ?? 0;
    return ListRow(
      leading: SizedBox.square(
        dimension: 40,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: PageThumbnail(path: pages?.firstOrNull?.thumbPath),
        ),
      ),
      title: document.title,
      caption:
          '$count ${count == 1 ? 'page' : 'pages'} · '
          '${DateFormat('d MMM yyyy').format(document.updatedAt)}',
      captionIsMeta: true,
      onTap: onTap,
    );
  }
}
