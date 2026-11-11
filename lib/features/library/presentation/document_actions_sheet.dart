import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/spacing.dart';
import '../../../core/widgets/list_group.dart';
import '../../../core/widgets/modal_close_button.dart';
import '../domain/document.dart';

enum DocumentAction { share, rename, delete }

Future<DocumentAction?> showDocumentActions(
  BuildContext context,
  Document document,
) => showShadSheet<DocumentAction>(
  context: context,
  barrierLabel: 'Dismiss',
  side: ShadSheetSide.bottom,
  builder: (context) {
    ListRow row(
      IconData icon,
      String label,
      DocumentAction action, {
      bool destructive = false,
    }) => ListRow(
      icon: icon,
      title: label,
      destructive: destructive,
      trailing: const SizedBox.shrink(),
      onTap: () => Navigator.of(context).pop(action),
    );
    return ShadSheet(
      title: ModalTitle(document.title),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.lg),
        child: ListGroup(
          children: [
            row(LucideIcons.share2, 'Share PDF', DocumentAction.share),
            row(LucideIcons.pencil, 'Rename', DocumentAction.rename),
            row(
              LucideIcons.trash2,
              'Delete',
              DocumentAction.delete,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  },
);
