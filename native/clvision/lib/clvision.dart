// ignore_for_file: non_constant_identifier_names
@DefaultAsset('package:clvision/clvision.dart')
library;

import 'dart:ffi';

@Native<Int32 Function(Pointer<Uint8>, Int32, Int32, Int32, Pointer<Float>)>(
  isLeaf: true,
)
external int clv_detect_gray(
  Pointer<Uint8> gray,
  int w,
  int h,
  int stride,
  Pointer<Float> corners,
);

/// timings: decode, warp, enhance, encode (ms), output mean.
@Native<
  Int32 Function(
    Pointer<Uint8>,
    Int32,
    Pointer<Float>,
    Int32,
    Int32,
    Pointer<Pointer<Uint8>>,
    Pointer<Double>,
  )
>()
external int clv_still_jpeg(
  Pointer<Uint8> jpeg,
  int len,
  Pointer<Float> corners,
  int outW,
  int outH,
  Pointer<Pointer<Uint8>> out,
  Pointer<Double> timings,
);

@Native<Int32 Function(Pointer<Uint8>, Int32, Int32, Pointer<Pointer<Uint8>>)>()
external int clv_encode_bgr_jpeg(
  Pointer<Uint8> bgr,
  int w,
  int h,
  Pointer<Pointer<Uint8>> out,
);

@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void clv_free(Pointer<Void> p);

@Native<Pointer<Char> Function()>()
external Pointer<Char> clv_build_info();

@Native<Int32 Function()>(isLeaf: true)
external int clv_num_threads();
