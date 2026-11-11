import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/licenses/about_sheet.dart';
import '../../capture/domain/scan_mode.dart';
import '../../capture/presentation/scan_mode_sheet.dart';
import '../../export/data/export_providers.dart';
import '../../library/data/library_providers.dart';
import '../../library/domain/document.dart';
import '../../library/domain/document_repository.dart';
import '../../library/presentation/document_actions_sheet.dart';
import '../../library/presentation/files_tab.dart';
import '../../library/presentation/library_providers.dart';
import '../../library/presentation/rename_dialog.dart';
import '../../library/presentation/settings_sheet.dart';
import '../../scan_engine/presentation/start_scan.dart';
import 'document_picker_sheet.dart';
import 'floating_nav.dart';
import 'home_tab.dart';

/// The app shell at `/`: Home and Files tabs under a floating bottom bar.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _undoWindow = Duration(seconds: 5);
  static const _barClearance = 112.0;

  late final DocumentRepository _documents = ref.read(
    documentRepositoryProvider,
  );
  // Deleting is hard and removes files, so it is deferred until the undo window ends.
  // Held here, not in a tab, so both tabs hide the document and undo survives a tab switch.
  final _pendingDeletes = <String, Timer>{};
  final _hidden = <String>{};
  var _tab = ShellTab.home;

  @override
  void dispose() {
    for (final entry in _pendingDeletes.entries) {
      entry.value.cancel();
      unawaited(_documents.delete(entry.key));
    }
    super.dispose();
  }

  Future<void> _scanIn(ScanMode mode) async {
    unawaited(ref.read(lastScanModeProvider.notifier).set(mode));
    await startScan(context, ref, mode: mode);
  }

  Future<void> _chooseModeAndScan() async {
    final mode = await showScanModeSheet(context);
    if (mode != null && mounted) await _scanIn(mode);
  }

  Future<void> _export(List<Document> documents) async {
    final document = await showDocumentPicker(context, documents);
    if (document != null && mounted) await _share(document);
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
        ShadToast.destructive(
          offset: _toastOffset,
          title: const Text('Could not export this PDF'),
        ),
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
        offset: _toastOffset,
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

  double get _bottomInset =>
      _barClearance + MediaQuery.paddingOf(context).bottom;

  // Toasts sit above the floating bar so they never cover it.
  Offset get _toastOffset => Offset(16, _bottomInset - 24);

  @override
  Widget build(BuildContext context) {
    final visible = ref
        .watch(documentsProvider)
        .value
        ?.where((d) => !_hidden.contains(d.id))
        .toList();
    final lastMode = ref.watch(lastScanModeProvider).value ?? ScanMode.document;
    final bottomInset = _bottomInset;
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _tab.index,
              children: [
                HomeTab(
                  documents: visible,
                  bottomInset: bottomInset,
                  onHelp: () => showAboutSheet(context),
                  onSettings: () => showSettingsSheet(context),
                  onScan: _chooseModeAndScan,
                  onExport: visible == null || visible.isEmpty
                      ? null
                      : () => _export(visible),
                  onOpenFiles: () => setState(() => _tab = ShellTab.files),
                  onMenu: _openMenu,
                ),
                FilesTab(
                  documents: visible,
                  onMenu: _openMenu,
                  bottomInset: bottomInset,
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: FloatingNav(
              tab: _tab,
              onTab: (tab) => setState(() => _tab = tab),
              quickScanMode: lastMode,
              onQuickScan: () => _scanIn(lastMode),
              onChooseMode: _chooseModeAndScan,
            ),
          ),
        ],
      ),
    );
  }
}
