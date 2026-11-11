import 'dart:ffi';

import 'package:ffi/ffi.dart';

// Bindings for native/clvision/include/clvision.h; keep the two in sync.
// The hook bundles libclvision under this library's asset id.

abstract final class ClvStatus {
  static const ok = 0;
  static const noQuad = 1;
  static const notImplemented = -1;
  static const invalidArgument = -2;
  static const decodeFailed = -3;
  static const encodeFailed = -4;
  static const internalError = -5;
}

final class ClvYuvFrame extends Struct {
  external Pointer<Uint8> y;
  external Pointer<Uint8> u;
  external Pointer<Uint8> v;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int yRowStride;
  @Int32()
  external int uvRowStride;
  @Int32()
  external int uvPixelStride;
  @Int32()
  external int rotationDegrees;
}

final class ClvRenderParams extends Struct {
  /// `PageFilter.index`.
  @Int32()
  external int filter;
  @Int32()
  external int rotationQuarterTurns;
  @Float()
  external double aspectRatio;
  @Int32()
  external int maxLongSide;
}

@Native<Pointer<Utf8> Function()>(symbol: 'clv_opencv_version', isLeaf: true)
external Pointer<Utf8> clvOpencvVersion();

@Native<Int32 Function(Pointer<ClvYuvFrame>, Pointer<Float>, Pointer<Float>)>(
  symbol: 'clv_detect_frame',
)
external int clvDetectFrame(
  Pointer<ClvYuvFrame> frame,
  Pointer<Float> cornersOut,
  Pointer<Float> confidenceOut,
);

@Native<Int32 Function(Pointer<Uint8>, Int32, Pointer<Float>, Pointer<Float>)>(
  symbol: 'clv_detect_image',
)
external int clvDetectImage(
  Pointer<Uint8> encoded,
  int length,
  Pointer<Float> cornersOut,
  Pointer<Float> confidenceOut,
);

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Int32,
    Pointer<Float>,
    Pointer<ClvRenderParams>,
    Pointer<Pointer<Uint8>>,
    Pointer<Int32>,
  )
>(symbol: 'clv_render_page')
external int clvRenderPage(
  Pointer<Uint8> encoded,
  int length,
  Pointer<Float> quad,
  Pointer<ClvRenderParams> params,
  Pointer<Pointer<Uint8>> jpegOut,
  Pointer<Int32> jpegLengthOut,
);

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Int32,
    Int32,
    Pointer<Pointer<Uint8>>,
    Pointer<Int32>,
  )
>(symbol: 'clv_thumbnail')
external int clvThumbnail(
  Pointer<Uint8> encoded,
  int length,
  int maxSide,
  Pointer<Pointer<Uint8>> jpegOut,
  Pointer<Int32> jpegLengthOut,
);

@Native<Void Function(Pointer<Void>)>(symbol: 'clv_free', isLeaf: true)
external void clvFree(Pointer<Void> buffer);

String openCvVersion() => clvOpencvVersion().toDartString();
