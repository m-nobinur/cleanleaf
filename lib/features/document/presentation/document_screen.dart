import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/round_icon_button.dart';
import '../../export/domain/convert_format.dart';
import '../../export/presentation/convert_sheet.dart';
import '../../library/data/library_providers.dart';
import '../../library/domain/document.dart';
import '../../library/domain/document_page.dart';
import '../../library/presentation/document_actions_sheet.dart';
import '../../library/presentation/document_card.dart';
import '../../library/presentation/library_providers.dart';
import '../../library/presentation/rename_dialog.dart';
import 'extract_text_slot.dart';

/// `/document/:docId`: the document's pages and what you can do with them.
class DocumentScreen extends ConsumerStatefulWidget {
  const DocumentScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends ConsumerState<DocumentScreen> {
  // Edit acts on this page; a single tap on a thumbnail selects it.
  var _selected = 0;

  void _back() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.library);

  Future<void> _rename(Document document) async {
    final title = await showRenameDialog(context, document.title);
    if (title != null) {
      await ref.read(documentRepositoryProvider).rename(document.id, title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final documents = ref.watch(documentsProvider).value;
    final document = documents
        ?.where((d) => d.id == widget.documentId)
        .firstOrNull;
    final pages =
        ref.watch(documentPagesProvider(widget.documentId)).value ??
        const <DocumentPage>[];
    final selectedIndex = pages.isEmpty ? 0 : _selected % pages.length;
    final selected = pages.isEmpty ? null : pages[selectedIndex];
    final extractText = ref.watch(extractTextActionProvider);
    final count = pages.length;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.xl,
        Spacing.sm,
        Spacing.xl,
        Spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoundIconButton(
            icon: LucideIcons.arrowLeft,
            label: 'Back',
            onPressed: _back,
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            document?.title ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.greeting.copyWith(
              fontSize: 30,
              color: colors.foreground,
            ),
          ),
          if (document != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              '$count ${count == 1 ? 'PAGE' : 'PAGES'} · '
              '${DateFormat('d MMM yyyy').format(document.updatedAt).toUpperCase()}',
              style: theme.textTheme.monoLabel.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            if (count > 1)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  'Tap a page to choose which one Edit opens.',
                  style: theme.textTheme.muted,
                ),
              ),
          ],
        ],
      ),
    );

    if (documents != null && document == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                child: Text(
                  'This document no longer exists.',
                  style: theme.textTheme.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.xl,
                  0,
                  Spacing.xl,
                  Spacing.lg,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: Spacing.md,
                  crossAxisSpacing: Spacing.md,
                  childAspectRatio: 0.74,
                ),
                itemCount: count,
                itemBuilder: (_, i) => _PageTile(
                  key: ValueKey(pages[i].id),
                  page: pages[i],
                  number: i + 1,
                  total: count,
                  selected: i == selectedIndex,
                  onTap: () => setState(() => _selected = i),
                ),
              ),
            ),
            if (document != null)
              _ActionBar(
                actions: [
                  _Action(
                    icon: LucideIcons.crop,
                    label: 'Edit',
                    primary: true,
                    onTap: selected == null
                        ? null
                        : () => context.push(AppRoutes.editor(selected.id)),
                  ),
                  _Action(
                    icon: LucideIcons.fileOutput,
                    label: 'Convert',
                    onTap: () => convertDocument(context, ref, document),
                  ),
                  if (extractText != null)
                    _Action(
                      icon: LucideIcons.scanText,
                      label: 'Extract text',
                      onTap: () => extractText(context, document.id),
                    ),
                  _Action(
                    icon: LucideIcons.share2,
                    label: 'Share PDF',
                    onTap: () => shareDocumentAs(
                      context,
                      ref,
                      ConvertFormat.pdf,
                      document.id,
                    ),
                  ),
                  _Action(
                    icon: LucideIcons.pencil,
                    label: 'Rename',
                    onTap: () => _rename(document),
                  ),
                  _Action(
                    icon: LucideIcons.trash2,
                    label: 'Delete',
                    destructive: true,
                    onTap: () => context.pop(DocumentAction.delete),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.page,
    required this.number,
    required this.total,
    required this.selected,
    required this.onTap,
  });

  final DocumentPage page;
  final int number;
  final int total;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    const inset = Spacing.sm;
    return Semantics(
      label: 'Page $number of $total',
      selected: selected,
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(inset),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: selected ? colors.primary : colors.hairline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.md - inset),
                  // Unrendered pages fall back to the uncropped original.
                  child: PageThumbnail(
                    path: page.thumbPath ?? page.originalPath,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm, left: 2),
                child: Text(
                  number.toString().padLeft(2, '0'),
                  style: theme.textTheme.monoMeta.copyWith(
                    color: selected ? colors.primary : colors.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool destructive;
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.actions});

  final List<_Action> actions;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.md,
        ),
        child: Row(
          children: [
            for (final action in actions)
              Expanded(child: _ActionButton(action: action)),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final _Action action;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final foreground = action.primary
        ? colors.primaryForeground
        : action.destructive
        ? colors.destructive
        : colors.foreground;
    final enabled = action.onTap != null;
    return Semantics(
      label: action.label,
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      onTap: action.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action.onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: action.primary ? colors.primary : colors.badge,
                  shape: BoxShape.circle,
                  border: action.primary
                      ? null
                      : Border.all(color: colors.hairline),
                ),
                child: Icon(action.icon, size: 22, color: foreground),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.caption.copyWith(
                  color: action.destructive
                      ? colors.destructive
                      : colors.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
