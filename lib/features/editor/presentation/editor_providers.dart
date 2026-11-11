import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';
import '../../library/data/library_providers.dart';
import '../../library/domain/document_page.dart';

typedef PageImage = ({ImageProvider image, Size size});

// About 2x a phone's screen width: sharp under the loupe without a 12 MP decode.
const _maxDecodeSide = 2048;

final editorPageProvider = FutureProvider.autoDispose
    .family<DocumentPage, String>((ref, pageId) async {
      final page = await ref.watch(pageRepositoryProvider).get(pageId);
      if (page == null) throw StateError('Page $pageId not found');
      return page;
    });

final pageImageProvider = FutureProvider.autoDispose.family<PageImage, String>((
  ref,
  originalPath,
) async {
  final file = await ref.watch(fileStoreProvider).resolve(originalPath);
  final image = ResizeImage(
    FileImage(file),
    width: _maxDecodeSide,
    height: _maxDecodeSide,
    policy: ResizeImagePolicy.fit,
  );
  return (image: image, size: await _decodedSize(image));
});

// The decoded frame, not the file header, so EXIF orientation is applied.
Future<Size> _decodedSize(ImageProvider provider) {
  final completer = Completer<Size>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(
        Size(info.image.width.toDouble(), info.image.height.toDouble()),
      );
      info.dispose();
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
