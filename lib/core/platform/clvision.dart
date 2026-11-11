import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

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
  static const modelNotLoaded = -6;
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
  external int rotationDegrees;
  @Float()
  external double aspectRatio;
  @Int32()
  external int maxLongSide;
  @Float()
  external double brightness;
  @Float()
  external double contrast;
  @Float()
  external double saturation;
  @Float()
  external double sharpness;
  @Float()
  external double straightenDegrees;

  /// 1 encodes PNG instead of JPEG.
  @Int32()
  external int encodePng;
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

@Native<Int32 Function(Pointer<Uint8>, Int32)>(symbol: 'clv_model_load')
external int clvModelLoad(Pointer<Uint8> model, int length);

@Native<Int32 Function()>(symbol: 'clv_model_loaded', isLeaf: true)
external int clvModelLoaded();

@Native<Int32 Function(Pointer<Float>, Pointer<Float>)>(symbol: 'clv_model_run')
external int clvModelRun(Pointer<Float> input, Pointer<Float> heatmapsOut);

/// 1 when fp16 runs, 0 when fp32 runs, negative [ClvStatus] on failure.
@Native<Int32 Function(Int32)>(symbol: 'clv_model_set_fp16')
external int clvModelSetFp16(int enabled);

String openCvVersion() => clvOpencvVersion().toDartString();

/// DocAligner LC100 (decisions.md D-11); `clv_model_load` takes its bytes.
const docAlignerAsset = 'assets/models/lc100_fp16_padzero.tflite';
const modelInputSize = 256;
const modelHeatmapSize = 128;

/// Loads DocAligner into clvision, off the UI thread. Kotlin's live detection
/// shares the same library instance (D-39), so this enables it too.
/// fp16 is the shipped default (decisions.md D-43); it falls back to fp32 on
/// CPUs without fp16 arithmetic.
Future<void> loadDocAligner({bool fp16 = true}) async {
  final data = await rootBundle.load(docAlignerAsset);
  final model = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final status = await Isolate.run(() {
    final loaded = _loadModel(model);
    if (loaded == ClvStatus.ok && fp16) clvModelSetFp16(1);
    return loaded;
  });
  if (status != ClvStatus.ok) {
    throw StateError('clv_model_load failed with status $status');
  }
}

int _loadModel(Uint8List model) => using((arena) {
  final bytes = arena<Uint8>(model.length)
    ..asTypedList(model.length).setAll(0, model);
  return clvModelLoad(bytes, model.length);
});
