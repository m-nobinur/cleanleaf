import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../../library/domain/document.dart';

Future<Document?> showDocumentPicker(
  BuildContext context,
  List<Document> documents, {
  required String title,
  required String description,
}) => showShadSheet<Document>(
  context: context,
  side: ShadSheetSide.bottom,
  builder: (context) {
    final theme = ShadTheme.of(context);
    return ShadSheet(
      radius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      removeBorderRadiusWhenTiny: false,
      title: Text(title),
      description: Text(description),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(top: Spacing.md),
          children: [
            for (final document in documents)
              ShadButton.ghost(
                width: double.infinity,
                height: 56,
                mainAxisAlignment: MainAxisAlignment.start,
                leading: const Icon(LucideIcons.fileText, size: 20),
                onPressed: () => Navigator.of(context).pop(document),
                child: Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          document.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        DateFormat('d MMM').format(document.updatedAt),
                        style: theme.textTheme.monoMeta.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  },
);
