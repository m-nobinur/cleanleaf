import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/spacing.dart';
import '../domain/document.dart';

enum DocumentAction { share, rename, delete }

Future<DocumentAction?> showDocumentActions(
  BuildContext context,
  Document document,
) => showShadSheet<DocumentAction>(
  context: context,
  side: ShadSheetSide.bottom,
  builder: (_) => ShadSheet(
    title: Text(document.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    child: const Padding(
      padding: EdgeInsets.only(top: Spacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionTile(
            icon: LucideIcons.share2,
            label: 'Share PDF',
            action: DocumentAction.share,
          ),
          _ActionTile(
            icon: LucideIcons.pencil,
            label: 'Rename',
            action: DocumentAction.rename,
          ),
          _ActionTile(
            icon: LucideIcons.trash2,
            label: 'Delete',
            action: DocumentAction.delete,
            destructive: true,
          ),
        ],
      ),
    ),
  ),
);

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.action,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final DocumentAction action;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? ShadTheme.of(context).colorScheme.destructive
        : null;
    return ShadButton.ghost(
      width: double.infinity,
      height: 52,
      mainAxisAlignment: MainAxisAlignment.start,
      leading: Icon(icon, size: 20, color: color),
      foregroundColor: color,
      onPressed: () => Navigator.of(context).pop(action),
      child: Text(label),
    );
  }
}
