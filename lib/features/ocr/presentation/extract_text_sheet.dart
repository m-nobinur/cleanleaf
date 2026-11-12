import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/modal_close_button.dart';
import '../../export/domain/plain_text.dart';
import '../data/ocr_providers.dart';
import '../domain/ocr_language.dart';
import '../domain/ocr_repository.dart';
import '../domain/ocr_result.dart';

/// The text of [pageIds], in order, with Copy, Share and a language choice
/// that reads the pages again. Opens on the stored text in whatever language
/// it was read; unread pages are read first (D-13a).
Future<void> showExtractTextSheet(
  BuildContext context, {
  required String title,
  required List<String> pageIds,
}) => showShadSheet<void>(
  context: context,
  barrierLabel: 'Dismiss',
  side: ShadSheetSide.bottom,
  builder: (_) => ExtractTextSheet(title: title, pageIds: pageIds),
);

typedef _Read = ({String text, int unread});

class ExtractTextSheet extends ConsumerStatefulWidget {
  const ExtractTextSheet({
    super.key,
    required this.title,
    required this.pageIds,
  });

  final String title;
  final List<String> pageIds;

  @override
  ConsumerState<ExtractTextSheet> createState() => _ExtractTextSheetState();
}

class _ExtractTextSheetState extends ConsumerState<ExtractTextSheet> {
  // Shown once the stored text says which language it was read in.
  OcrLanguage? _language;
  // ignore(): a fast failure must not count as unhandled before the
  // FutureBuilder subscribes on the next build.
  late Future<_Read> _read = _extract(null)..ignore();
  var _pagesRead = 0;

  Future<_Read> _extract(OcrLanguage? language) async {
    final repository = ref.read(ocrRepositoryProvider);
    final texts = <OcrResult?>[];
    for (final id in widget.pageIds) {
      try {
        texts.add(await repository.extractText(id, language));
      } on OcrFailed {
        texts.add(null);
      }
      if (mounted && language == _language) {
        setState(() => _pagesRead = texts.length);
      }
    }
    final read = texts.nonNulls.toList();
    if (read.isEmpty) throw OcrFailed(widget.pageIds.first);
    if (language == null && mounted) {
      final languages = read.map((t) => t.language).toSet();
      setState(
        () => _language = languages.length == 1
            ? languages.single
            : OcrLanguage.auto,
      );
    }
    return (text: plainText(texts), unread: texts.length - read.length);
  }

  void _readIn(OcrLanguage language) => setState(() {
    _language = language;
    _pagesRead = 0;
    _read = _extract(language)..ignore();
  });

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ShadToaster.of(context).show(const ShadToast(title: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return ShadSheet(
      title: const ModalTitle('Extract text'),
      description: Padding(
        padding: const EdgeInsets.only(right: Spacing.xl),
        child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.md),
        child: FutureBuilder(
          future: _read,
          builder: (context, snapshot) {
            final read = snapshot.data;
            final reading = snapshot.connectionState != ConnectionState.done;
            final text = reading ? null : read?.text;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Spacing.md,
              children: [
                _LanguageSwitch(
                  selected: _language,
                  onChanged: reading && _language == null ? null : _readIn,
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: 120,
                    maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.muted,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: reading
                        ? _Reading(
                            done: _pagesRead,
                            total: widget.pageIds.length,
                          )
                        : snapshot.hasError
                        ? _Failed(
                            onRetry: () =>
                                _readIn(_language ?? OcrLanguage.auto),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(Spacing.md),
                            child: SelectableText(
                              text!.isEmpty ? 'No text found.' : text,
                              style: text.isEmpty
                                  ? theme.textTheme.muted
                                  : theme.textTheme.p.copyWith(
                                      color: colors.foreground,
                                    ),
                            ),
                          ),
                  ),
                ),
                if (!reading && (read?.unread ?? 0) > 0)
                  Text(
                    read!.unread == 1
                        ? '1 page could not be read.'
                        : '${read.unread} pages could not be read.',
                    style: theme.textTheme.muted,
                  ),
                Row(
                  spacing: Spacing.sm,
                  children: [
                    Expanded(
                      child: ShadButton.outline(
                        enabled: text?.isNotEmpty ?? false,
                        leading: const Icon(LucideIcons.copy, size: 18),
                        onPressed: () => _copy(text!),
                        child: const Text('Copy'),
                      ),
                    ),
                    Expanded(
                      child: ShadButton(
                        enabled: text?.isNotEmpty ?? false,
                        leading: const Icon(LucideIcons.share2, size: 18),
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(text: text, subject: widget.title),
                        ),
                        child: const Text('Share'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LanguageSwitch extends StatelessWidget {
  const _LanguageSwitch({required this.selected, required this.onChanged});

  final OcrLanguage? selected;

  /// Null while the stored language is still unknown.
  final ValueChanged<OcrLanguage>? onChanged;

  static const _labels = {
    OcrLanguage.auto: 'Auto',
    OcrLanguage.english: 'English',
    OcrLanguage.bangla: 'বাংলা',
  };

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.xs),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        children: [
          for (final MapEntry(key: language, value: label) in _labels.entries)
            Expanded(
              child: Semantics(
                label: label,
                button: true,
                selected: language == selected,
                enabled: onChanged != null,
                excludeSemantics: true,
                onTap: () => onChanged?.call(language),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged?.call(language),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: language == selected
                          ? colors.background
                          : colors.muted,
                      borderRadius: BorderRadius.circular(Radii.sm - 2),
                      border: Border.all(
                        color: language == selected
                            ? colors.hairline
                            : colors.muted,
                      ),
                    ),
                    child: Text(
                      label,
                      style: theme.textTheme.small.copyWith(
                        color: language == selected
                            ? colors.foreground
                            : colors.mutedForeground,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Spacing.sm,
          children: [
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            Text(
              total == 1
                  ? 'Reading text…'
                  : 'Reading text… page ${(done + 1).clamp(1, total)} of $total',
              style: theme.textTheme.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Spacing.sm,
          children: [
            Text("Couldn't read the text.", style: theme.textTheme.muted),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              leading: const Icon(LucideIcons.rotateCw, size: 16),
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
