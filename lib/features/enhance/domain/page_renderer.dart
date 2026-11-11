import 'dart:typed_data';

import '../../../core/geometry/quad.dart';
import '../../library/domain/document_page.dart';

abstract interface class PageRenderer {
  /// Flattens [quad] of the original photo, turns it [rotation] degrees
  /// clockwise and applies [filter]; returns JPEG bytes.
  Future<Uint8List> render(
    String originalPath,
    Quad quad,
    int rotation,
    PageFilter filter,
    Map<String, double> params,
  );
}
