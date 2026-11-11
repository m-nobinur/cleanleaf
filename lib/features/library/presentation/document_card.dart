import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../domain/document.dart';
import 'library_providers.dart';

enum LibraryLayout { grid, list }

class DocumentCard extends ConsumerWidget {
  const DocumentCard({
    super.key,
    required this.document,
    required this.layout,
    required this.onTap,
    required this.onMenu,
  });

  final Document document;
  final LibraryLayout layout;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ShadTheme.of(context);
    final pages = ref.watch(documentPagesProvider(document.id)).value;
    final count = pages?.length ?? 0;
    final meta =
        '$count ${count == 1 ? 'page' : 'pages'} · '
        '${DateFormat('d MMM yyyy').format(document.updatedAt)}';
    final thumb = _Thumbnail(path: pages?.firstOrNull?.thumbPath);

    final caption = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                document.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.small.copyWith(
                  color: theme.colorScheme.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.monoMeta.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        Semantics(
          label: 'More actions for ${document.title}',
          button: true,
          excludeSemantics: true,
          onTap: onMenu,
          child: ShadIconButton.ghost(
            width: 40,
            height: 40,
            foregroundColor: theme.colorScheme.mutedForeground,
            icon: const Icon(LucideIcons.ellipsis, size: 18),
            onPressed: onMenu,
          ),
        ),
      ],
    );

    const inset = Spacing.sm;
    final framedThumb = ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md - inset),
      child: thumb,
    );

    return Semantics(
      label: '${document.title}, $meta',
      container: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onMenu,
        child: Container(
          padding: const EdgeInsets.all(inset),
          decoration: BoxDecoration(
            color: theme.colorScheme.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: theme.colorScheme.hairline),
          ),
          child: switch (layout) {
            LibraryLayout.grid => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: framedThumb),
                Padding(
                  padding: const EdgeInsets.only(left: Spacing.xs, top: 2),
                  child: caption,
                ),
              ],
            ),
            LibraryLayout.list => SizedBox(
              height: 64,
              child: Row(
                children: [
                  AspectRatio(aspectRatio: 1, child: framedThumb),
                  const SizedBox(width: Spacing.md),
                  Expanded(child: caption),
                ],
              ),
            ),
          },
        ),
      ),
    );
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ShadTheme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.muted,
      child: Center(
        child: Icon(
          LucideIcons.fileText,
          color: colors.mutedForeground,
          size: 28,
        ),
      ),
    );
    final file = path == null
        ? null
        : ref.watch(thumbFileProvider(path!)).value;
    if (file == null) return placeholder;
    return Image.file(
      file,
      fit: BoxFit.cover,
      cacheWidth: 480,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
