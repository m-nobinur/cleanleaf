import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../data/ocr_providers.dart';

/// "Reading text…" while any page of [documentId] waits for or is in OCR;
/// nothing otherwise.
class ReadingTextChip extends ConsumerWidget {
  const ReadingTextChip({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading =
        ref.watch(readingDocumentIdsProvider).value?.contains(documentId) ??
        false;
    if (!reading) return const SizedBox.shrink();
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Spacing.xs,
        children: [
          Icon(LucideIcons.scanText, size: 12, color: colors.mutedForeground),
          Text(
            'Reading text…',
            style: theme.textTheme.monoMeta.copyWith(
              fontSize: 11,
              color: colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
