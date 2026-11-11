import 'dart:ffi';
import 'dart:typed_data';

import 'package:clvision/clvision.dart';
import 'package:ffi/ffi.dart';

import 'spike_types.dart';

// Candidate B from Dart: the C++ core over FFI. Kotlin calls the same .so.

/// Zero-copy: leaf calls take the typed data's address.
Float32List? detectFrameB(Uint8List plane, int width, int height, int stride) {
  final out = Float32List(8);
  final found = clv_detect_gray(
    plane.address,
    width,
    height,
    stride,
    out.address,
  );
  return found == 1 ? out : null;
}

StillResult stillB(Uint8List jpeg, Float32List corners, int outW, int outH) {
  return using((arena) {
    final input = arena<Uint8>(jpeg.length);
    input.asTypedList(jpeg.length).setAll(0, jpeg);
    final c = arena<Float>(8)..asTypedList(8).setAll(0, corners);
    final out = arena<Pointer<Uint8>>();
    final t = arena<Double>(5);
    final len = clv_still_jpeg(input, jpeg.length, c, outW, outH, out, t);
    final encoded = Uint8List.fromList(out.value.asTypedList(len));
    clv_free(out.value.cast());
    return StillResult(
      decodeMs: t[0],
      warpMs: t[1],
      enhanceMs: t[2],
      encodeMs: t[3],
      mean: t[4],
      jpeg: encoded,
    );
  });
}

Uint8List encodeBgrB(Uint8List bgr, int w, int h) {
  return using((arena) {
    final input = arena<Uint8>(bgr.length)
      ..asTypedList(bgr.length).setAll(0, bgr);
    final out = arena<Pointer<Uint8>>();
    final len = clv_encode_bgr_jpeg(input, w, h, out);
    final encoded = Uint8List.fromList(out.value.asTypedList(len));
    clv_free(out.value.cast());
    return encoded;
  });
}

String buildInfoB() => clv_build_info().cast<Utf8>().toDartString();

int numThreadsB() => clv_num_threads();
