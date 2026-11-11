import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gallery_import/data/detect_still_quad.dart';
import '../../library/data/library_providers.dart';
import '../domain/document_camera.dart';
import 'camera_scan.dart';
import 'pigeon_document_camera.dart';

final documentCameraProvider = Provider<DocumentCamera>(
  (ref) => PigeonDocumentCamera(),
);

final cameraScanProvider = Provider(
  (ref) => CameraScan(
    detect: detectStillQuad,
    documents: ref.watch(documentRepositoryProvider),
    pages: ref.watch(pageRepositoryProvider),
  ),
);
