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
    required this.onImport,
    required this.onEdit,
    required this.onConvert,
    required this.onOpen,
    required this.onMenu,
  });

  /// Newest first; null while loading.
  final List<Document>? documents;
  final double bottomInset;
  final VoidCallback onHelp;
  final VoidCallback onSettings;
  final VoidCallback onScan;
  final VoidCallback onImport;

  /// Edit and Convert are null when there are no documents.
  final VoidCallback? onEdit;
  final VoidCallback? onConvert;
  final void Function(Document) onOpen;
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
    final query = _query.trim().toLowerCase();
    final shown = query.isEmpty
        ? documents.take(_recentCount).toList()
        : documents
              .where((d) => d.title.toLowerCase().contains(query))
              .toList();
    const gutter = EdgeInsets.symmetric(horizontal: Spacing.xl);

    // Fixed top bar, so scrolled content never runs up under the status bar.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Spacing.sm),
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
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(bottom: widget.bottomInset),
            children: [
              const SizedBox(height: Spacing.xxl),
              Padding(
                padding: gutter,
                child: Text(
                  'Scan, clean,\nshare.',
                  style: theme.textTheme.greeting.copyWith(
                    color: colors.foreground,
                  ),
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
                    BentoTile(
                      key: const ValueKey('tile-import'),
                      tone: TileTone.mist,
                      icon: LucideIcons.images,
                      title: 'Import',
                      caption: 'From your photos',
                      onTap: widget.onImport,
                    ),
                    BentoTile(
                      key: const ValueKey('tile-edit'),
                      tone: TileTone.ember,
                      icon: LucideIcons.crop,
                      title: 'Edit',
                      caption: widget.onEdit == null
                          ? 'Scan something first'
                          : 'Crop, filters, rotate',
                      onTap: widget.onEdit,
                    ),
                    BentoTile(
                      key: const ValueKey('tile-convert'),
                      tone: TileTone.ink,
                      icon: LucideIcons.fileOutput,
                      title: 'Convert',
                      caption: widget.onConvert == null
                          ? 'Scan something first'
                          : 'PDF, JPG, PNG',
                      onTap: widget.onConvert,
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
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: Spacing.md),
                    itemBuilder: (_, i) => SizedBox(
                      width: 156,
                      child: DocumentCard(
                        key: ValueKey(shown[i].id),
                        document: shown[i],
                        layout: LibraryLayout.grid,
                        onTap: () => widget.onOpen(shown[i]),
                        onMenu: () => widget.onMenu(shown[i]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
