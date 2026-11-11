import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/document_camera.dart';
import 'pigeon_document_camera.dart';

final documentCameraProvider = Provider<DocumentCamera>(
  (ref) => PigeonDocumentCamera(),
);
