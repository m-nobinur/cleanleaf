import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'core/geometry/quad.dart';
import 'features/enhance/data/native_page_renderer.dart';
import 'features/library/domain/document_page.dart';

// Times a 12 MP render on the device: run with -t and read
// `adb logcat -s flutter:I` until `CLBENCH DONE`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await runRenderBench((await getTemporaryDirectory()).path, debugPrint);
  } catch (e) {
    debugPrint('CLBENCH FAILED $e');
  } finally {
    debugPrint('CLBENCH DONE');
  }
  runApp(const SizedBox.shrink());
}

const _benchQuad = (
  topLeft: (x: 0.08, y: 0.06),
  topRight: (x: 0.93, y: 0.09),
  bottomRight: (x: 0.95, y: 0.94),
  bottomLeft: (x: 0.05, y: 0.92),
);

Future<void> runRenderBench(String dir, void Function(String) log) async {
  const width = 4080, height = 3072, runs = 4;
  const renderer = NativePageRenderer();
  log('CLBENCH cpus ${Platform.numberOfProcessors}');
  final watch = Stopwatch()..start();
  final bmp = syntheticPageBmp(width, height, shadow: 0.55);
  final jpeg = await renderer.thumbnail(bmp, maxSide: math.max(width, height));
  final input = File('$dir/bench_input.jpg')..writeAsBytesSync(jpeg);
  log(
    'CLBENCH input ${width}x$height ${jpeg.length} B '
    'built in ${watch.elapsedMilliseconds} ms',
  );
  for (final (filter, rotation) in [
    for (final rotation in [0, 90])
      for (final filter in PageFilter.values) (filter, rotation),
  ]) {
    final name = '${filter.name} rot=$rotation';
    final times = <int>[];
    late Uint8List out;
    for (var i = 0; i < runs; i++) {
      watch.reset();
      out = await renderer.render(
        input.path,
        _benchQuad,
        rotation,
        filter,
        const {},
      );
      times.add(watch.elapsedMilliseconds);
    }
    final warm = times.skip(1).toList()..sort();
    log(
      'CLBENCH render $name first=${times.first} ms '
      'warm median=${warm[warm.length ~/ 2]} max=${warm.last} ms '
      'out=${out.length} B',
    );
    watch.reset();
    await renderer.thumbnail(out);
    log('CLBENCH thumbnail $name ${watch.elapsedMilliseconds} ms');
  }
}

/// 24-bit BMP of a light page with text-like bars, a grey ramp strip, a dark
/// marker near its top-left and dust specks, on a noisy desk. Content lies in
/// scene fractions x 0.17–0.75, y 0.18–0.78, so any quad around that holds it.
/// [shadow] is how much darker the left edge is than the right (0..1).
Uint8List syntheticPageBmp(
  int width,
  int height, {
  Quad quad = _benchQuad,
  double shadow = 0,
}) {
  final rowSize = (width * 3 + 3) & ~3;
  final bytes = Uint8List(54 + rowSize * height);
  ByteData.sublistView(bytes)
    ..setUint16(0, 0x4d42, Endian.little) // 'BM'
    ..setUint32(2, bytes.length, Endian.little)
    ..setUint32(10, 54, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, width, Endian.little)
    ..setInt32(22, height, Endian.little) // positive: rows run bottom-up
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(34, rowSize * height, Endian.little);
  final corners = [
    for (final c in quad.corners) (x: c.x * width, y: c.y * height),
  ];
  var seed = 0x2545f491;
  int noise() {
    seed = (seed ^ seed << 13) & 0xffffffff;
    seed ^= seed >> 17;
    return seed = (seed ^ seed << 5) & 0xffffffff;
  }

  for (var y = 0; y < height; y++) {
    final fy = y / height;
    var offset = 54 + (height - 1 - y) * rowSize;
    for (var x = 0; x < width; x++) {
      final fx = x / width;
      final r = noise();
      int b, g, red;
      if (_inside(corners, x + 0.5, y + 0.5)) {
        final luma = _pageLuma(fx, fy, r);
        b = luma - 8;
        g = luma - 3;
        red = luma + 2;
      } else {
        b = 50;
        g = 70;
        red = 95;
      }
      final light = 1 - shadow * (1 - fx);
      bytes[offset++] = ((b + (r & 15) - 8) * light).round().clamp(0, 255);
      bytes[offset++] = ((g + (r >> 4 & 15) - 8) * light).round().clamp(0, 255);
      bytes[offset++] = ((red + (r >> 8 & 15) - 8) * light).round().clamp(
        0,
        255,
      );
    }
  }
  return bytes;
}

int _pageLuma(double fx, double fy, int random) {
  if (fx >= 0.17 && fx < 0.22 && fy >= 0.18 && fy < 0.25) return 20;
  if (fx >= 0.70 && fx < 0.75 && fy >= 0.30 && fy < 0.78) {
    return (20 + 200 * (fy - 0.30) / 0.48).round();
  }
  if (fx >= 0.25 && fx < 0.60 && fy >= 0.30 && fy < 0.79) {
    final inLine = (fy - 0.30) % 0.035 < 0.012;
    final inWord = (fx * 50).floor() % 5 != 4;
    if (inLine && inWord) return 30;
  }
  return (random >> 12) & 0xfff == 0 ? 60 : 232; // dust specks
}

// Clockwise convex quad, y down: inside when on the inner side of every edge.
bool _inside(List<({double x, double y})> c, double x, double y) {
  for (var i = 0; i < 4; i++) {
    final a = c[i], b = c[(i + 1) % 4];
    if ((b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x) < 0) return false;
  }
  return true;
}
