import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/bento_tile.dart';
import '../../../core/widgets/round_icon_button.dart';
import '../../library/domain/document.dart';
import '../../library/presentation/document_card.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.documents,
    required this.bottomInset,
    required this.onHelp,
    required this.onSettings,
    required this.onScan,
    required this.onExport,
    required this.onOpenFiles,
    required this.onMenu,
  });

  /// Newest first; null while loading.
  final List<Document>? documents;
  final double bottomInset;
  final VoidCallback onHelp;
  final VoidCallback onSettings;
  final VoidCallback onScan;

  /// Null when there is nothing to export.
  final VoidCallback? onExport;
  final VoidCallback onOpenFiles;
  final void Function(Document) onMenu;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const _recentCount = 10;
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final documents = widget.documents ?? const <Document>[];
    final count = documents.length;
    final query = _query.trim().toLowerCase();
    final shown = query.isEmpty
        ? documents.take(_recentCount).toList()
        : documents
              .where((d) => d.title.toLowerCase().contains(query))
              .toList();
    const gutter = EdgeInsets.symmetric(horizontal: Spacing.xl);

    return ListView(
      padding: EdgeInsets.only(top: Spacing.sm, bottom: widget.bottomInset),
      children: [
        Padding(
          padding: gutter,
          child: Row(
            children: [
              RoundIconButton(
                icon: LucideIcons.circleQuestionMark,
                label: 'About Cleanleaf',
                onPressed: widget.onHelp,
              ),
              const Spacer(),
              RoundIconButton(
                icon: LucideIcons.settings,
                label: 'Settings',
                onPressed: widget.onSettings,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.xxl),
        Padding(
          padding: gutter,
          child: Text(
            'Scan, clean,\nshare.',
            style: theme.textTheme.greeting.copyWith(color: colors.foreground),
          ),
        ),
        const SizedBox(height: Spacing.xl),
        Padding(
          padding: gutter,
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: Spacing.md,
            crossAxisSpacing: Spacing.md,
            childAspectRatio: 0.98,
            children: [
              BentoTile(
                key: const ValueKey('tile-scan'),
                tone: TileTone.leaf,
                icon: LucideIcons.scanLine,
                title: 'Scan',
                caption: 'Documents, ID cards, receipts',
                onTap: widget.onScan,
              ),
              const BentoTile(
                key: ValueKey('tile-import'),
                tone: TileTone.mist,
                icon: LucideIcons.images,
                title: 'Import',
                caption: 'From your photos',
                badge: 'SOON',
              ),
              BentoTile(
                key: const ValueKey('tile-export'),
                tone: TileTone.ember,
                icon: LucideIcons.share2,
                title: 'Export',
                caption: widget.onExport == null
                    ? 'Scan something first'
                    : 'PDF and share',
                onTap: widget.onExport,
              ),
              BentoTile(
                key: const ValueKey('tile-files'),
                tone: TileTone.ink,
                icon: LucideIcons.folder,
                title: 'Files',
                caption: '$count ${count == 1 ? 'document' : 'documents'}',
                onTap: widget.onOpenFiles,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Padding(
          padding: gutter,
          child: ShadInput(
            placeholder: const Text('Search documents'),
            leading: Padding(
              padding: const EdgeInsets.only(left: Spacing.xs),
              child: Icon(
                LucideIcons.search,
                size: 18,
                color: colors.mutedForeground,
              ),
            ),
            decoration: ShadDecoration(
              border: ShadBorder.all(
                color: colors.hairline,
                radius: BorderRadius.circular(Radii.full),
              ),
              focusedBorder: ShadBorder.all(
                color: colors.ring,
                radius: BorderRadius.circular(Radii.full),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const SizedBox(height: Spacing.xl),
        Padding(
          padding: gutter,
          child: Text(
            query.isEmpty ? 'RECENT' : 'RESULTS',
            style: theme.textTheme.monoLabel.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (shown.isEmpty)
          Padding(
            padding: gutter,
            child: Text(
              query.isEmpty
                  ? 'Your scans will show up here.'
                  : 'No documents match "${_query.trim()}".',
              style: theme.textTheme.muted,
            ),
          )
        else
          SizedBox(
            height: 212,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: gutter,
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(width: Spacing.md),
              itemBuilder: (_, i) => SizedBox(
                width: 156,
                child: DocumentCard(
                  key: ValueKey(shown[i].id),
                  document: shown[i],
                  layout: LibraryLayout.grid,
                  onTap: () {},
                  onMenu: () => widget.onMenu(shown[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
