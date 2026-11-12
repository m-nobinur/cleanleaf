import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/data/library_providers.dart';
import '../../ocr/presentation/extract_text_sheet.dart';

/// The document view's "Extract text" action: the text sheet over every page
/// of the document. Null hides it.
final extractTextActionProvider =
    Provider<Future<void> Function(BuildContext context, String documentId)?>(
      (ref) => (context, documentId) async {
        final document = await ref
            .read(documentRepositoryProvider)
            .get(documentId);
        final pages = await ref
            .read(pageRepositoryProvider)
            .getByDocument(documentId);
        if (document == null || pages.isEmpty || !context.mounted) return;
        await showExtractTextSheet(
          context,
          title: document.title,
          pageIds: [for (final page in pages) page.id],
        );
      },
    );
