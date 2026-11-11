import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../gallery_import/data/detect_still_quad.dart';
import '../../library/data/library_providers.dart';
import '../domain/document_camera.dart';
import '../domain/scan_mode.dart';
import 'camera_scan.dart';
import 'decode_still_code.dart';
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

/// Picks a photo and reads a code from it. Null when the user cancels;
/// `code` is null when the photo has none.
final galleryCodeProvider =
    Provider<Future<({ScannedCode? code})?> Function(CodeFamily)>(
      (ref) => (family) async {
        final photo = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (photo == null) return null;
        return (code: await decodeStillCode(photo.path, family));
      },
    );
