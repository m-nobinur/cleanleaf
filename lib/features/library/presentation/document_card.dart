import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/app_theme.dart';
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
    final radius = BorderRadius.circular(Spacing.lg);

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
                  color: theme.colorScheme.primaryForeground,
                ),
              ),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.muted.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        Semantics(
          label: 'More actions for ${document.title}',
          button: true,
          child: ShadIconButton.ghost(
            width: 40,
            height: 40,
            foregroundColor: theme.colorScheme.primaryForeground,
            icon: const Icon(LucideIcons.ellipsis, size: 18),
            onPressed: onMenu,
          ),
        ),
      ],
    );

    final captionBar = Container(
      color: Brand.ink,
      padding: const EdgeInsets.only(left: Spacing.md),
      child: caption,
    );

    return Semantics(
      label: '${document.title}, $meta',
      container: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onMenu,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.colorScheme.card,
            borderRadius: radius,
            border: Border.all(color: theme.colorScheme.border),
          ),
          child: switch (layout) {
            LibraryLayout.grid => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: thumb),
                captionBar,
              ],
            ),
            LibraryLayout.list => SizedBox(
              height: 72,
              child: Row(
                children: [
                  AspectRatio(aspectRatio: 1, child: thumb),
                  Expanded(child: captionBar),
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
