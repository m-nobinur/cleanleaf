import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/data/library_providers.dart';
import '../../library/domain/document_page.dart';
import '../domain/page_renderer.dart';
import 'native_page_renderer.dart';

final pageRendererProvider = Provider<PageRenderer>(
  (ref) => const NativePageRenderer(),
);

// Read from the repository, not the editor's provider: that one is still alive
// under the editor and holds the page from before the crop was saved.
final enhancePageProvider = FutureProvider.autoDispose
    .family<DocumentPage, String>((ref, pageId) async {
      final page = await ref.watch(pageRepositoryProvider).get(pageId);
      if (page == null) throw StateError('Page $pageId not found');
      return page;
    });
