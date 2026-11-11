import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/router/app_routes.dart';
import '../../library/data/library_providers.dart';
import '../data/detect_still_quad.dart';
import '../data/gallery_import.dart';

final galleryImportProvider = Provider(
  (ref) => GalleryImport(
    pick: () async =>
        (await ImagePicker().pickImage(source: ImageSource.gallery))?.path,
    detect: detectStillQuad,
    documents: ref.watch(documentRepositoryProvider),
    pages: ref.watch(pageRepositoryProvider),
  ),
);

var _importing = false;

/// Entry point for the home Import tile, the files tab and the capture screen.
Future<void> importFromGallery(BuildContext context, WidgetRef ref) async {
  if (_importing) return;
  _importing = true;
  try {
    final page = await ref.read(galleryImportProvider)();
    if (page == null || !context.mounted) return;
    await context.push(AppRoutes.editor(page.id));
  } on Object {
    if (!context.mounted) return;
    ShadToaster.of(context).show(
      const ShadToast.destructive(title: Text('Could not import that photo')),
    );
  } finally {
    _importing = false;
  }
}
