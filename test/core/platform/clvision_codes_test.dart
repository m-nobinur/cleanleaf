import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cleanleaf/core/platform/clvision.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Fixtures come from tool/generate_code_fixtures.py: camera-like frames with a
// code at a known pixels-per-module (ppm).
const _dir = 'test/fixtures/codes';

final _expected = (jsonDecode(
  File('$_dir/expected.json').readAsStringSync(),
) as Map<String, dynamic>).cast<String, String?>();

typedef _Read = ({int status, String? text, String? format});

const _both = ClvCodes.matrix | ClvCodes.linear;

_Read _decodeImage(String name, {int formats = _both}) => using((arena) {
  final bytes = File('$_dir/$name').readAsBytesSync();
  final input = arena<Uint8>(bytes.length)
    ..asTypedList(bytes.length).setAll(0, bytes);
  final code = arena<ClvCode>();
  final status = clvDecodeImageCodes(input, bytes.length, formats, code);
  return _result(status, code);
});

/// Decodes the fixture as a camera frame's luma plane, rotated as a phone's
/// sensor delivers it, with row padding.
_Read _decodeFrame(String name, {int rotation = 0}) => using((arena) {
  final gray = img.decodeJpg(File('$_dir/$name').readAsBytesSync())!;
  final turned = switch (rotation) {
    90 => img.copyRotate(gray, angle: -90),
    270 => img.copyRotate(gray, angle: 90),
    _ => gray,
  };
  final stride = turned.width + 32;
  final y = arena<Uint8>(stride * turned.height);
  for (var row = 0; row < turned.height; row++) {
    for (var x = 0; x < turned.width; x++) {
      y[row * stride + x] = turned.getPixel(x, row).r.toInt();
    }
  }
  final frame = arena<ClvYuvFrame>()
    ..ref.y = y
    ..ref.u = y
    ..ref.v = y
    ..ref.width = turned.width
    ..ref.height = turned.height
    ..ref.yRowStride = stride
    ..ref.uvRowStride = stride
    ..ref.uvPixelStride = 2
    ..ref.rotationDegrees = rotation;
  final code = arena<ClvCode>();
  return _result(clvDecodeFrameCodes(frame, _both, code), code);
});

_Read _result(int status, Pointer<ClvCode> code) {
  if (status != ClvStatus.ok) return (status: status, text: null, format: null);
  final read = takeCode(code.ref);
  return (status: status, text: read.text, format: read.format);
}

void main() {
  // The reticle keeps codes at or above these densities on a 640x480 frame.
  const mustRead = [
    'qr_v10_2.5ppm.jpg',
    'qr_v10_3.0ppm.jpg',
    'qr_v10_4.0ppm.jpg',
    'qr_v2_small.jpg',
    'qr_utf8.jpg',
    'qr_v10_1280.jpg',
    'ean13_1.5ppm.jpg',
    'ean13_2.0ppm.jpg',
    'code128_2.0ppm.jpg',
  ];

  for (final name in mustRead) {
    test('reads $name from a still and a frame', () {
      final still = _decodeImage(name);
      expect(still.status, ClvStatus.ok);
      expect(still.text, _expected[name]);
      final frame = _decodeFrame(name, rotation: 90);
      expect(frame.text, _expected[name]);
    });
  }

  test('reports format names', () {
    expect(_decodeImage('qr_v2_small.jpg').format, 'QR Code');
    expect(_decodeImage('ean13_2.0ppm.jpg').format, 'EAN-13');
    expect(_decodeImage('code128_2.0ppm.jpg').format, 'Code 128');
  });

  test('looks only for the requested family', () {
    expect(
      _decodeImage('qr_v2_small.jpg', formats: ClvCodes.linear).status,
      ClvStatus.noCode,
    );
    expect(
      _decodeImage('ean13_2.0ppm.jpg', formats: ClvCodes.matrix).status,
      ClvStatus.noCode,
    );
  });

  test('finds nothing in a blank frame', () {
    expect(_decodeImage('no_code.jpg').status, ClvStatus.noCode);
    expect(_decodeFrame('no_code.jpg').status, ClvStatus.noCode);
  });

  test('rejects bad arguments', () {
    using((arena) {
      final code = arena<ClvCode>();
      expect(
        clvDecodeImageCodes(arena<Uint8>(4), 4, 0, code),
        ClvStatus.invalidArgument,
      );
      expect(
        clvDecodeImageCodes(arena<Uint8>(4), 4, _both, code),
        ClvStatus.decodeFailed,
      );
    });
  });

  test('density sweep (informational)', () {
    for (final name in _expected.keys.toList()..sort()) {
      final watch = Stopwatch()..start();
      final read = _decodeFrame(name, rotation: 90);
      // ignore: avoid_print
      print(
        'CODES $name read=${read.text == _expected[name]} '
        'frame_ms=${watch.elapsedMilliseconds}',
      );
    }
  });
}
