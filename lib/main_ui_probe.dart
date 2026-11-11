import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/licenses/third_party_licenses.dart';
import 'core/platform/clvision.dart';
import 'core/storage/storage_providers.dart';
import 'features/enhance/data/enhance_providers.dart';
import 'features/gallery_import/data/detect_still_quad.dart';
import 'features/library/data/library_providers.dart';
import 'features/library/domain/document_page.dart';

// Release probe for UI screenshots (T-036): when the library is empty, turns
// the real photos in <external files>/seed/ into rendered documents the way
// Save does, then runs the real app. "Lease agreement__2.jpg" is page 2 of
// "Lease agreement". Logs CLSEED lines and a final CLSEED DONE.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();
  final container = ProviderContainer();
  try {
    await _seed(container);
  } catch (e) {
    debugPrint('CLSEED ERROR $e');
  }
  debugPrint('CLSEED DONE');
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CleanleafApp(),
    ),
  );
}

Future<void> _seed(ProviderContainer container) async {
  final documents = container.read(documentRepositoryProvider);
  if ((await documents.watchAll().first).isNotEmpty) {
    debugPrint('CLSEED kept existing library');
    return;
  }
  final dir = Directory(
    p.join((await getExternalStorageDirectory())!.path, 'seed'),
  );
  final photos =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  await loadDocAligner();
  final pages = container.read(pageRepositoryProvider);
  final renderer = container.read(pageRendererProvider);
  final files = container.read(fileStoreProvider);
  final ids = <String, String>{};
  for (final photo in photos) {
    final title = p.basenameWithoutExtension(photo.path).split('__').first;
    final docId = ids[title] ??= (await documents.create(title)).id;
    final page = await pages.add(
      docId,
      original: photo.openRead(),
      detectedCorners: await detectStillQuad(photo.path),
      source: PageSource.gallery,
    );
    final original = (await files.resolve(page.originalPath)).path;
    final render = await renderer.render(
      original,
      page.corners,
      page.rotation,
      page.filter,
      page.filterParams,
    );
    await pages.saveRender(
      page.id,
      render: Stream.value(render),
      thumb: Stream.value(await renderer.thumbnail(render)),
    );
    debugPrint('CLSEED page "$title" ${p.basename(photo.path)}');
  }
}
