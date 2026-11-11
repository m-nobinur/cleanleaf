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
  }) {
    final filterIndex = filter.index;
    final aspectRatio = params[aspectRatioParam] ?? 0;
    return Isolate.run(
      () => _render(
        File(originalPath).readAsBytesSync(),
        quad,
        rotation,
        filterIndex,
        aspectRatio,
        maxLongSide,
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
  double aspectRatio,
  int maxLongSide,
) => using((arena) {
  final corners = arena<Float>(8);
  var i = 0;
  for (final corner in quad.corners) {
    corners[i++] = corner.x;
    corners[i++] = corner.y;
  }
  final params = arena<ClvRenderParams>();
  params.ref
    ..filter = filter
    ..rotationDegrees = rotation
    ..aspectRatio = aspectRatio
    ..maxLongSide = maxLongSide;
  return _callForJpeg(
    arena,
    encoded,
    (input, length, out, outLength) =>
        clvRenderPage(input, length, corners, params, out, outLength),
  );
}, malloc);

Uint8List _thumbnail(Uint8List encoded, int maxSide) => using(
  (arena) => _callForJpeg(
    arena,
    encoded,
    (input, length, out, outLength) =>
        clvThumbnail(input, length, maxSide, out, outLength),
  ),
  malloc,
);

Uint8List _callForJpeg(
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
