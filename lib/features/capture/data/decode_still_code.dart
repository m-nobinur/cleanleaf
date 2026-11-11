import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../../core/platform/clvision.dart';
import '../domain/document_camera.dart';
import '../domain/scan_mode.dart';

/// The first [family] code in a photo, or null when it has none.
Future<ScannedCode?> decodeStillCode(String imagePath, CodeFamily family) =>
    Isolate.run(() => _decode(File(imagePath).readAsBytesSync(), family));

ScannedCode? _decode(Uint8List encoded, CodeFamily family) => using((arena) {
  if (encoded.isEmpty) return null;
  final input = arena<Uint8>(encoded.length)
    ..asTypedList(encoded.length).setAll(0, encoded);
  final code = arena<ClvCode>();
  final formats = switch (family) {
    CodeFamily.matrix => ClvCodes.matrix,
    CodeFamily.linear => ClvCodes.linear,
  };
  final status = clvDecodeImageCodes(input, encoded.length, formats, code);
  return status == ClvStatus.ok ? takeCode(code.ref) : null;
}, malloc);
