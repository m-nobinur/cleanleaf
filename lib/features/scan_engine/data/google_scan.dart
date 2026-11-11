import 'dart:io';

import '../../library/domain/default_title.dart';
import '../../library/domain/document_page.dart';
import '../../library/domain/document_repository.dart';
import '../../library/domain/page_repository.dart';

/// Runs Google's scanner and stores its result as a new one-page document.
class GoogleScan {
  GoogleScan({
    required this.scan,
    required this.documents,
    required this.pages,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Returns the scanned JPEG path, or null when the user cancels.
  final Future<String?> Function() scan;
  final DocumentRepository documents;
  final PageRepository pages;
  final DateTime Function() _now;

  /// The new page, or null when cancelled.
  Future<DocumentPage?> call() async {
    final path = await scan();
    if (path == null) return null;
    final jpeg = File(path);
    final document = await documents.create(defaultDocumentTitle(_now()));
    try {
      // Google already cropped and enhanced it, so it is kept as the original.
      final page = await pages.add(
        document.id,
        original: jpeg.openRead(),
        detectedCorners: null,
        source: PageSource.googleScanner,
      );
      final edited = page.copyWith(filter: PageFilter.original);
      await pages.updateEdits(edited);
      await _deleteQuietly(jpeg);
      return edited;
    } catch (_) {
      await documents.delete(document.id);
      rethrow;
    }
  }

  // Best effort: a leftover cache file must never undo a saved scan.
  Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Ignored; it is in the cache dir, which Android clears.
    }
  }
}
