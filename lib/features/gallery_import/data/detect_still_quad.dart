import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../../core/geometry/quad.dart';
import '../../../core/platform/clvision.dart';

/// Corners in the EXIF-oriented frame (D-31), or null when no page is found
/// or detection is unavailable (the full frame is used instead).
Future<Quad?> detectStillQuad(String imagePath) =>
    Isolate.run(() => _detect(File(imagePath).readAsBytesSync()));

Quad? _detect(Uint8List encoded) => using((arena) {
  if (encoded.isEmpty) return null;
  final input = arena<Uint8>(encoded.length);
  input.asTypedList(encoded.length).setAll(0, encoded);
  final corners = arena<Float>(8);
  final status = clvDetectImage(input, encoded.length, corners, arena<Float>());
  if (status != ClvStatus.ok) return null;
  Point at(int i) => (x: corners[2 * i], y: corners[2 * i + 1]);
  return (
    topLeft: at(0),
    topRight: at(1),
    bottomRight: at(2),
    bottomLeft: at(3),
  );
}, malloc);
