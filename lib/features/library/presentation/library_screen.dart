import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/spacing.dart';
import '../../export/data/export_providers.dart';
import '../data/library_providers.dart';
import '../domain/document.dart';
import '../domain/document_repository.dart';
import 'document_actions_sheet.dart';
import 'document_card.dart';
import 'library_providers.dart';
import 'rename_dialog.dart';
import 'settings_sheet.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _undoWindow = Duration(seconds: 5);

  late final DocumentRepository _documents = ref.read(
    documentRepositoryProvider,
  );
  // Deleting is hard and removes files, so it is deferred until the undo window ends.
  final _pendingDeletes = <String, Timer>{};
  final _hidden = <String>{};
  var _layout = LibraryLayout.grid;

  @override
  void dispose() {
    for (final entry in _pendingDeletes.entries) {
      entry.value.cancel();
      unawaited(_documents.delete(entry.key));
    }
    super.dispose();
  }

  Future<void> _openMenu(Document document) async {
    final action = await showDocumentActions(context, document);
    if (!mounted) return;
    switch (action) {
      case DocumentAction.share:
        await _share(document);
      case DocumentAction.rename:
        final title = await showRenameDialog(context, document.title);
        if (title != null) await _documents.rename(document.id, title);
      case DocumentAction.delete:
        _delete(document);
      case null:
        break;
    }
  }

  Future<void> _share(Document document) async {
    try {
      await ref.read(shareDocumentPdfProvider)(document.id);
    } on Object {
      if (!mounted) return;
      ShadToaster.of(context).show(
        const ShadToast.destructive(title: Text('Could not export this PDF')),
      );
    }
  }

  void _delete(Document document) {
    setState(() => _hidden.add(document.id));
    _pendingDeletes[document.id]?.cancel();
    _pendingDeletes[document.id] = Timer(
      _undoWindow,
      () => _commitDelete(document.id),
    );
    final toaster = ShadToaster.of(context);
    toaster.show(
      ShadToast(
        title: Text('Deleted "${document.title}"'),
        duration: _undoWindow,
        action: ShadButton.outline(
          onPressed: () {
            _pendingDeletes.remove(document.id)?.cancel();
            setState(() => _hidden.remove(document.id));
            toaster.hide();
          },
          child: const Text('Undo'),
        ),
      ),
    );
  }

  Future<void> _commitDelete(String id) async {
    _pendingDeletes.remove(id);
    try {
      await _documents.delete(id);
    } catch (_) {
      if (mounted) setState(() => _hidden.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider);
    final visible = documents.value
        ?.where((d) => !_hidden.contains(d.id))
        .toList();
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              layout: _layout,
              onToggleLayout: () => setState(
                () => _layout = _layout == LibraryLayout.grid
                    ? LibraryLayout.list
                    : LibraryLayout.grid,
              ),
            ),
            Expanded(
              child: visible == null
                  ? const SizedBox.shrink()
                  : visible.isEmpty
                  ? const _EmptyState()
                  : _DocumentList(
                      documents: visible,
                      layout: _layout,
                      onMenu: _openMenu,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.xl,
                Spacing.sm,
                Spacing.xl,
                Spacing.xl,
              ),
              child: ShadButton(
                height: 52,
                leading: const Icon(LucideIcons.scanLine),
                onPressed: () => context.push(AppRoutes.capture),
                child: const Text('Scan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.layout, required this.onToggleLayout});

  final LibraryLayout layout;
  final VoidCallback onToggleLayout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.xl,
        Spacing.xl,
        Spacing.xl,
        Spacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('Library', style: ShadTheme.of(context).textTheme.h2),
          ),
          Semantics(
            label: layout == LibraryLayout.grid
                ? 'Switch to list view'
                : 'Switch to grid view',
            button: true,
            child: ShadIconButton.outline(
              width: 48,
              height: 48,
              icon: Icon(
                layout == LibraryLayout.grid
                    ? LucideIcons.list
                    : LucideIcons.layoutGrid,
                size: 20,
              ),
              onPressed: onToggleLayout,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Semantics(
            label: 'Settings',
            button: true,
            child: ShadIconButton.outline(
              width: 48,
              height: 48,
              icon: const Icon(LucideIcons.settings, size: 20),
              onPressed: () => showSettingsSheet(context),
            ),
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
  });

  final List<Document> documents;
  final LibraryLayout layout;
  final void Function(Document) onMenu;

  @override
  Widget build(BuildContext context) {
    Widget card(Document d) => DocumentCard(
      key: ValueKey(d.id),
      document: d,
      layout: layout,
      onTap: () {},
      onMenu: () => onMenu(d),
    );
    const padding = EdgeInsets.symmetric(horizontal: Spacing.xl);
    return switch (layout) {
      LibraryLayout.grid => GridView.builder(
        padding: padding,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: Spacing.md,
          crossAxisSpacing: Spacing.md,
          childAspectRatio: 0.78,
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
            Icon(
              LucideIcons.fileText,
              size: 40,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: Spacing.lg),
            Text('No documents yet', style: theme.textTheme.h4),
            const SizedBox(height: Spacing.sm),
            Text(
              'Tap Scan to capture your first document.',
              textAlign: TextAlign.center,
              style: theme.textTheme.muted,
            ),
          ],
        ),
      ),
    );
  }
}
