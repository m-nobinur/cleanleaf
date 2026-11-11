import 'dart:io';

import '../../../core/geometry/quad.dart';
import '../../library/domain/default_title.dart';
import '../../library/domain/document_page.dart';
import '../../library/domain/document_repository.dart';
import '../../library/domain/page_repository.dart';

/// Stores a picked photo as the original of a new one-page document.
class GalleryImport {
  GalleryImport({
    required this.pick,
    required this.detect,
    required this.documents,
    required this.pages,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The picked image's path, or null when the user cancels.
  final Future<String?> Function() pick;
  final Future<Quad?> Function(String imagePath) detect;
  final DocumentRepository documents;
  final PageRepository pages;
  final DateTime Function() _now;

  /// The new page, or null when cancelled.
  Future<DocumentPage?> call() async {
    final path = await pick();
    if (path == null) return null;
    final corners = await detect(path);
    final document = await documents.create(defaultDocumentTitle(_now()));
    try {
      return await pages.add(
        document.id,
        original: File(path).openRead(),
        detectedCorners: corners,
        source: PageSource.gallery,
      );
    } catch (_) {
      await documents.delete(document.id);
      rethrow;
    }
  }
}
