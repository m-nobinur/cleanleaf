import 'dart:math' as math;
import 'dart:typed_data';

import '../../../core/geometry/quad.dart';
import '../../library/domain/document_page.dart';

/// `params` key: long side / short side to snap the page to; absent or 0
/// keeps the quad's own shape.
const aspectRatioParam = 'aspectRatio';

/// Long side / short side of common page formats, for [aspectRatioParam].
enum PageAspect {
  a4(math.sqrt2),
  letter(11 / 8.5),
  id1(85.6 / 53.98),
  id3(125 / 88);

  const PageAspect(this.ratio);

  final double ratio;
}

const thumbnailMaxSide = 320;

abstract interface class PageRenderer {
  /// Flattens [quad] of the photo at the absolute [originalPath], turns it
  /// [rotation] degrees clockwise and applies [filter]; returns JPEG bytes.
  /// [maxLongSide] caps the output for previews; 0 renders at full size.
  Future<Uint8List> render(
    String originalPath,
    Quad quad,
    int rotation,
    PageFilter filter,
    Map<String, double> params, {
    int maxLongSide = 0,
  });

  /// Re-encodes an image as JPEG with its long side at most [maxSide];
  /// smaller images keep their size.
  Future<Uint8List> thumbnail(
    Uint8List image, {
    int maxSide = thumbnailMaxSide,
  });
}
