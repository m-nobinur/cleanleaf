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

/// Manual adjustments (decisions.md D-49), stored in `params` under their
/// [name]; absent or 0 leaves the page unchanged. Each runs from -[limit] to
/// [limit]: tone and sharpness have no effect on B&W, saturation none on
/// Grayscale or B&W.
enum Adjustment {
  brightness(1),
  contrast(1),
  saturation(1),
  sharpness(1),

  /// Degrees clockwise, after rotation; the page is zoomed to stay filled.
  straighten(45);

  const Adjustment(this.limit);

  final double limit;

  bool appliesTo(PageFilter filter) => switch (this) {
    straighten => true,
    saturation =>
      filter == PageFilter.original || filter == PageFilter.enhancedColor,
    _ => filter != PageFilter.blackWhite,
  };
}

const thumbnailMaxSide = 320;

abstract interface class PageRenderer {
  /// Flattens [quad] of the photo at the absolute [originalPath], turns it
  /// [rotation] degrees clockwise, applies [filter] and the [Adjustment]s in
  /// [params], and returns JPEG bytes.
  /// [maxLongSide] caps the output for previews; 0 renders at full size.
  /// [png] returns lossless PNG bytes instead.
  Future<Uint8List> render(
    String originalPath,
    Quad quad,
    int rotation,
    PageFilter filter,
    Map<String, double> params, {
    int maxLongSide = 0,
    bool png = false,
  });

  /// Re-encodes an image as JPEG with its long side at most [maxSide];
  /// smaller images keep their size.
  Future<Uint8List> thumbnail(
    Uint8List image, {
    int maxSide = thumbnailMaxSide,
  });
}
