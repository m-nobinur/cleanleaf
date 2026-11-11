import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/corner_brackets.dart';
import '../../../core/widgets/round_icon_button.dart';
import '../domain/document.dart';
import 'document_card.dart';

class FilesTab extends StatefulWidget {
  const FilesTab({
    super.key,
    required this.documents,
    required this.onMenu,
    required this.bottomInset,
  });

  /// Null while loading.
  final List<Document>? documents;
  final void Function(Document) onMenu;

  /// Space kept clear for the floating bottom bar.
  final double bottomInset;

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  var _layout = LibraryLayout.grid;

  @override
  Widget build(BuildContext context) {
    final documents = widget.documents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          count: documents?.length,
          layout: _layout,
          onToggleLayout: () => setState(
            () => _layout = _layout == LibraryLayout.grid
                ? LibraryLayout.list
                : LibraryLayout.grid,
          ),
        ),
        Expanded(
          child: documents == null
              ? const SizedBox.shrink()
              : documents.isEmpty
              ? const _EmptyState()
              : _DocumentList(
                  documents: documents,
                  layout: _layout,
                  onMenu: widget.onMenu,
                  bottomInset: widget.bottomInset,
                ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.layout,
    required this.onToggleLayout,
  });

  final int? count;
  final LibraryLayout layout;
  final VoidCallback onToggleLayout;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.xl,
        Spacing.lg,
        Spacing.xl,
        Spacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Files',
                  style: theme.textTheme.greeting.copyWith(fontSize: 34),
                ),
                if (count != null)
                  Text(
                    '$count ${count == 1 ? 'DOCUMENT' : 'DOCUMENTS'}',
                    style: theme.textTheme.monoLabel.copyWith(
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
              ],
            ),
          ),
          RoundIconButton(
            icon: layout == LibraryLayout.grid
                ? LucideIcons.list
                : LucideIcons.layoutGrid,
            label: layout == LibraryLayout.grid
                ? 'Switch to list view'
                : 'Switch to grid view',
            onPressed: onToggleLayout,
          ),
        ],
      ),
    );
  }
}

class _DocumentList extends StatelessWidget {
  const _DocumentList({
    required this.documents,
    required this.layout,
    required this.onMenu,
    required this.bottomInset,
  });

  final List<Document> documents;
  final LibraryLayout layout;
  final void Function(Document) onMenu;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    Widget card(Document d) => DocumentCard(
      key: ValueKey(d.id),
      document: d,
      layout: layout,
      onTap: () {},
      onMenu: () => onMenu(d),
    );
    final padding = EdgeInsets.fromLTRB(Spacing.xl, 0, Spacing.xl, bottomInset);
    return switch (layout) {
      LibraryLayout.grid => GridView.builder(
        padding: padding,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: Spacing.md,
          crossAxisSpacing: Spacing.md,
          childAspectRatio: 0.74,
        ),
        itemCount: documents.length,
        itemBuilder: (_, i) => card(documents[i]),
      ),
      LibraryLayout.list => ListView.separated(
        padding: padding,
        itemCount: documents.length,
        separatorBuilder: (_, _) => const SizedBox(height: Spacing.md),
        itemBuilder: (_, i) => card(documents[i]),
      ),
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 72,
              child: CornerBrackets(
                color: theme.colorScheme.primary,
                child: Icon(
                  LucideIcons.fileText,
                  size: 28,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text('No documents yet', style: theme.textTheme.tileTitle),
            const SizedBox(height: Spacing.sm),
            Text(
              'Tap + to scan your first document.',
              textAlign: TextAlign.center,
              style: theme.textTheme.muted,
            ),
          ],
        ),
      ),
    );
  }
}
