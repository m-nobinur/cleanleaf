import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../../core/geometry/quad.dart';
import '../../../core/platform/clvision.dart';
import '../../library/domain/document_page.dart';
import '../domain/page_renderer.dart';

final class RenderException implements Exception {
  const RenderException(this.status);

  /// A [ClvStatus] value.
  final int status;

  @override
  String toString() => 'RenderException: clvision status $status';
}

/// clvision over FFI; each call runs in its own short-lived isolate.
class NativePageRenderer implements PageRenderer {
  const NativePageRenderer();

  @override
  Future<Uint8List> render(
    String originalPath,
    Quad quad,
    int rotation,
    PageFilter filter,
    Map<String, double> params, {
    int maxLongSide = 0,
    bool png = false,
  }) {
    final filterIndex = filter.index;
    return Isolate.run(
      () => _render(
        File(originalPath).readAsBytesSync(),
        quad,
        rotation,
        filterIndex,
        params,
        maxLongSide,
        png,
      ),
    );
  }

  @override
  Future<Uint8List> thumbnail(
    Uint8List image, {
    int maxSide = thumbnailMaxSide,
  }) => Isolate.run(() => _thumbnail(image, maxSide));
}

Uint8List _render(
  Uint8List encoded,
  Quad quad,
  int rotation,
  int filter,
  Map<String, double> params,
  int maxLongSide,
  bool png,
) => using((arena) {
  final corners = arena<Float>(8);
  var i = 0;
  for (final corner in quad.corners) {
    corners[i++] = corner.x;
    corners[i++] = corner.y;
  }
  double adjustment(Adjustment a) => params[a.name] ?? 0;
  // malloc doesn't zero, so every field is set.
  final native = arena<ClvRenderParams>();
  native.ref
    ..filter = filter
    ..rotationDegrees = rotation
    ..aspectRatio = params[aspectRatioParam] ?? 0
    ..maxLongSide = maxLongSide
    ..brightness = adjustment(Adjustment.brightness)
    ..contrast = adjustment(Adjustment.contrast)
    ..saturation = adjustment(Adjustment.saturation)
    ..sharpness = adjustment(Adjustment.sharpness)
    ..straightenDegrees = adjustment(Adjustment.straighten)
    ..encodePng = png ? 1 : 0;
  return _callForImage(
    arena,
    encoded,
    (input, length, out, outLength) =>
        clvRenderPage(input, length, corners, native, out, outLength),
  );
}, malloc);

Uint8List _thumbnail(Uint8List encoded, int maxSide) => using(
  (arena) => _callForImage(
    arena,
    encoded,
    (input, length, out, outLength) =>
        clvThumbnail(input, length, maxSide, out, outLength),
  ),
  malloc,
);

Uint8List _callForImage(
  Arena arena,
  Uint8List encoded,
  int Function(
    Pointer<Uint8> input,
    int length,
    Pointer<Pointer<Uint8>> out,
    Pointer<Int32> outLength,
  )
  call,
) {
  if (encoded.isEmpty) throw const RenderException(ClvStatus.invalidArgument);
  final input = arena<Uint8>(encoded.length);
  input.asTypedList(encoded.length).setAll(0, encoded);
  final out = arena<Pointer<Uint8>>();
  final outLength = arena<Int32>();
  final status = call(input, encoded.length, out, outLength);
  if (status != ClvStatus.ok) throw RenderException(status);
  try {
    return Uint8List.fromList(out.value.asTypedList(outLength.value));
  } finally {
    clvFree(out.value.cast());
  }
}
