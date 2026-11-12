@DefaultAsset('package:cleanleaf/core/platform/clvision.dart')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cleanleaf/core/platform/clvision.dart';
import 'package:ffi/ffi.dart';

// The app reads PP-OCR from Kotlin only, so these bindings live with the tests.

const ppOcrDetAsset = 'assets/models/ppocr_v6s_det960_fp16w.tflite';
const ppOcrRecAsset = 'assets/models/ppocr_v6s_rec_latin_dynw_fp16w.tflite';
const ppOcrDictAsset = 'assets/models/ppocr_v6s_rec_latin_dict.txt';
const clvCancelled = 3;

final class _ClvOcr extends Opaque {}

@Native<
  Pointer<_ClvOcr> Function(
    Pointer<Uint8>,
    Int32,
    Pointer<Uint8>,
    Int32,
    Pointer<Uint8>,
    Int32,
    Int32,
    Int32,
  )
>(symbol: 'clv_ocr_create')
external Pointer<_ClvOcr> _create(
  Pointer<Uint8> det,
  int detLength,
  Pointer<Uint8> rec,
  int recLength,
  Pointer<Uint8> dict,
  int dictLength,
  int fp16,
  int threads,
);

@Native<Void Function(Pointer<_ClvOcr>)>(symbol: 'clv_ocr_destroy')
external void _destroy(Pointer<_ClvOcr> ocr);

@Native<
  Int32 Function(
    Pointer<_ClvOcr>,
    Pointer<Uint8>,
    Int32,
    Int32,
    Pointer<Int32>,
    Pointer<Pointer<Uint8>>,
    Pointer<Int32>,
  )
>(symbol: 'clv_ocr_read')
external int _read(
  Pointer<_ClvOcr> ocr,
  Pointer<Uint8> encoded,
  int length,
  int stopIfNonLatin,
  Pointer<Int32> cancel,
  Pointer<Pointer<Uint8>> jsonOut,
  Pointer<Int32> jsonLengthOut,
);

/// The bundled PP-OCR engine on the host, as the Kotlin engine creates it.
class HostPpOcr {
  HostPpOcr({bool fp16 = true, int threads = 4}) {
    _handle = using(
      (arena) => _create(
        _copy(arena, File(ppOcrDetAsset).readAsBytesSync()),
        File(ppOcrDetAsset).lengthSync(),
        _copy(arena, File(ppOcrRecAsset).readAsBytesSync()),
        File(ppOcrRecAsset).lengthSync(),
        _copy(arena, File(ppOcrDictAsset).readAsBytesSync()),
        File(ppOcrDictAsset).lengthSync(),
        fp16 ? 1 : 0,
        threads,
      ),
    );
    if (_handle == nullptr) throw StateError('clv_ocr_create failed');
  }

  late final Pointer<_ClvOcr> _handle;

  /// The decoded `clv_ocr_read` JSON; throws with the status on failure.
  /// [cancelled] sets the cancel flag before reading.
  Map<String, dynamic> read(
    List<int> encoded, {
    bool stopIfNonLatin = false,
    bool cancelled = false,
  }) => using((arena) {
    final cancel = arena<Int32>()..value = cancelled ? 1 : 0;
    final json = arena<Pointer<Uint8>>();
    final length = arena<Int32>();
    final status = _read(
      _handle,
      _copy(arena, encoded),
      encoded.length,
      stopIfNonLatin ? 1 : 0,
      cancel,
      json,
      length,
    );
    if (status != ClvStatus.ok) throw ClvOcrException(status);
    final text = utf8.decode(json.value.asTypedList(length.value));
    clvFree(json.value.cast());
    return jsonDecode(text) as Map<String, dynamic>;
  });

  void dispose() => _destroy(_handle);
}

class ClvOcrException implements Exception {
  ClvOcrException(this.status);

  final int status;

  @override
  String toString() => 'clv_ocr_read status $status';
}

Pointer<Uint8> _copy(Arena arena, List<int> bytes) =>
    arena<Uint8>(bytes.length)..asTypedList(bytes.length).setAll(0, bytes);
