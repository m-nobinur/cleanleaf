import 'dart:typed_data';

import 'package:cleanleaf/core/geometry/quad.dart';

abstract interface class QuadDetector {
  /// Corners are normalized to the upright image (fixtures carry no EXIF
  /// orientation tag); null means no document in frame.
  Future<Quad?> detect(Uint8List encodedImage);
}
