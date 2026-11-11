import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/core/platform/clvision.dart';
import 'package:cleanleaf/features/enhance/data/native_page_renderer.dart';
import 'package:cleanleaf/features/enhance/domain/page_renderer.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:cleanleaf/main_render_bench.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../capture/detection_benchmark_harness.dart' show loadLabels;

const renderer = NativePageRenderer();
const sceneWidth = 1200;
const sceneHeight = 900;
const Quad sceneQuad = (
  topLeft: (x: 0.125, y: 0.111),
  topRight: (x: 0.875, y: 0.144),
  bottomRight: (x: 0.9, y: 0.911),
  bottomLeft: (x: 0.1, y: 0.878),
);
// The dark marker's centre in the flattened, unrotated page.
const marker = (x: 0.097, y: 0.131);

late Directory temp;

void main() {
  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('cleanleaf_render_');
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  group('synthetic page', () {
    late String plain;
    late String shadowed;
    late String deepShadow;
    setUpAll(() async {
      plain = await writeScene('plain.jpg');
      shadowed = await writeScene('shadowed.jpg', shadow: 0.55);
      deepShadow = await writeScene('deep_shadow.jpg', shadow: 0.8);
    });

    test('full frame without a filter is an identity', () async {
      final input = decode(File(plain).readAsBytesSync());
      final out = decode(await render(plain, fullFrame, PageFilter.original));
      expect((out.width, out.height), (sceneWidth, sceneHeight));
      expect(meanAbsDiff(input, out), lessThan(0.5));
    });

    test('output size is the longer of each pair of opposite edges', () async {
      final bytes = await render(plain, sceneQuad, PageFilter.original);
      expectSize(
        decode(bytes),
        naturalSize(sceneQuad, sceneWidth, sceneHeight),
      );
      expect(jpegComponents(bytes), 3);
    });

    test('aspect snap keeps the long side', () async {
      final out = decode(
        await render(
          plain,
          sceneQuad,
          PageFilter.original,
          params: {aspectRatioParam: PageAspect.a4.ratio},
        ),
      );
      final (w, _) = naturalSize(sceneQuad, sceneWidth, sceneHeight);
      expectSize(out, (w, (w / math.sqrt2).round()));
    });

    test('maxLongSide caps the output', () async {
      final out = decode(
        await render(plain, sceneQuad, PageFilter.original, maxLongSide: 320),
      );
      final (w, h) = naturalSize(sceneQuad, sceneWidth, sceneHeight);
      expectSize(out, (320, (h * 320 / w).round()));
    });

    for (final rotation in [0, 90, 180, 270]) {
      test('rotation $rotation turns the flattened page clockwise', () async {
        final out = decode(
          await render(
            plain,
            sceneQuad,
            PageFilter.original,
            rotation: rotation,
          ),
        );
        final (w, h) = naturalSize(sceneQuad, sceneWidth, sceneHeight);
        expectSize(out, rotation % 180 == 0 ? (w, h) : (h, w));
        final at = rotate(marker, rotation);
        final mirror = rotate((x: 1 - marker.x, y: marker.y), rotation);
        expect(meanLumaAt(out, at), lessThan(80));
        expect(meanLumaAt(out, mirror), greaterThan(150));
      });
    }

    test('EXIF orientation is applied before the quad', () async {
      final upright = decode(File(plain).readAsBytesSync());
      final stored = img.copyRotate(upright, angle: -90)
        ..exif.imageIfd.orientation = 6;
      final bytes = img.encodeJpg(stored, quality: 95);
      // package:image bakes the tag in on decode, so upright again means it's there.
      expect((stored.width, stored.height), (sceneHeight, sceneWidth));
      expect(decode(bytes).width, sceneWidth);
      final path = '${temp.path}/exif6.jpg';
      File(path).writeAsBytesSync(bytes);

      // Colour and grayscale decodes are separate paths.
      for (final filter in [PageFilter.original, PageFilter.blackWhite]) {
        final out = decode(await render(path, sceneQuad, filter));
        expectSize(out, naturalSize(sceneQuad, sceneWidth, sceneHeight));
        expect(meanLumaAt(out, marker), lessThan(80), reason: filter.name);
      }

      final thumb = decode(await renderer.thumbnail(bytes));
      expectSize(thumb, (320, 240));
    });

    test('B&W is binary; Grayscale keeps mid-tones', () async {
      final bw = await render(plain, sceneQuad, PageFilter.blackWhite);
      final gray = await render(plain, sceneQuad, PageFilter.grayscale);
      expect(jpegComponents(bw), 1);
      expect(jpegComponents(gray), 1);
      expect(midtoneFraction(decode(bw)), lessThan(0.01));
      expect(midtoneFraction(decode(gray)), greaterThan(0.01));
    });

    test('Enhanced and Grayscale flatten a shadow', () async {
      final original = unevenness(
        decode(await render(shadowed, sceneQuad, PageFilter.original)),
      );
      for (final filter in [PageFilter.enhancedColor, PageFilter.grayscale]) {
        final enhanced = unevenness(
          decode(await render(shadowed, sceneQuad, filter)),
        );
        expect(enhanced, lessThan(original * 0.25), reason: filter.name);
      }
    });

    test('B&W keeps deeply shadowed paper white', () async {
      final bw = decode(
        await render(deepShadow, sceneQuad, PageFilter.blackWhite),
      );
      // Blank paper left of the text, about 36% as bright as the lightest paper.
      expect(meanLumaAt(bw, (x: 0.06, y: 0.6)), greaterThan(200));
      expect(meanLumaAt(bw, marker), lessThan(80));
    });

    test('thumbnail fits the long side and never upscales', () async {
      final page = await render(plain, sceneQuad, PageFilter.grayscale);
      final thumb = await renderer.thumbnail(page);
      final (w, h) = naturalSize(sceneQuad, sceneWidth, sceneHeight);
      expectSize(decode(thumb), (
        thumbnailMaxSide,
        (h * thumbnailMaxSide / w).round(),
      ));
      expect(jpegComponents(thumb), 1);

      final small = decode(await renderer.thumbnail(page, maxSide: 2000));
      expectSize(small, (w, h));
    });

    test('bad input throws', () async {
      Matcher status(int s) =>
          throwsA(isA<RenderException>().having((e) => e.status, 'status', s));
      final junk = '${temp.path}/junk.jpg';
      File(junk).writeAsBytesSync(List.filled(64, 7));
      await expectLater(
        render(junk, sceneQuad, PageFilter.original),
        status(ClvStatus.decodeFailed),
      );
      const bowTie = (
        topLeft: (x: 0.1, y: 0.1),
        topRight: (x: 0.9, y: 0.9),
        bottomRight: (x: 0.9, y: 0.1),
        bottomLeft: (x: 0.1, y: 0.9),
      );
      await expectLater(
        render(plain, bowTie, PageFilter.original),
        status(ClvStatus.invalidArgument),
      );
      await expectLater(
        render(plain, sceneQuad, PageFilter.original, rotation: 45),
        status(ClvStatus.invalidArgument),
      );
      await expectLater(
        render('${temp.path}/missing.jpg', sceneQuad, PageFilter.original),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('detection-v0 fixtures', () {
    final source = Directory('.local/fixtures/detection-v0');
    final labelsFile = File('${source.path}/labels.json');
    final skip = labelsFile.existsSync() ? null : 'no fixtures at $source';
    // SmartDoc datasheet, synthetic shadowed A4, synthetic ID card.
    const fixtures = <String, PageAspect?>{
      'f001.jpg': null,
      'f199.jpg': PageAspect.a4,
      'f162.jpg': PageAspect.id1,
    };

    for (final MapEntry(key: name, value: aspect) in fixtures.entries) {
      test('$name: size, aspect, binary B&W', () async {
        final quad = loadLabels(labelsFile)[name]!.quad!;
        final path = '${temp.path}/$name';
        File('${source.path}/$name').copySync(path);
        final input = decode(File(path).readAsBytesSync());
        final (w, h) = naturalSize(quad, input.width, input.height);

        expectSize(decode(await render(path, quad, PageFilter.original)), (
          w,
          h,
        ));
        if (aspect != null) {
          final snapped = decode(
            await render(
              path,
              quad,
              PageFilter.original,
              params: {aspectRatioParam: aspect.ratio},
            ),
          );
          final long = math.max(w, h);
          final short = (long / aspect.ratio).round();
          expectSize(snapped, w >= h ? (long, short) : (short, long));
        }
        final bw = decode(await render(path, quad, PageFilter.blackWhite));
        final gray = decode(await render(path, quad, PageFilter.grayscale));
        expect(midtoneFraction(bw), lessThan(0.01));
        expect(midtoneFraction(gray), greaterThan(midtoneFraction(bw)));
      }, skip: skip);
    }

    test('f199.jpg: Enhanced flattens the shadow', () async {
      const name = 'f199.jpg';
      final quad = loadLabels(labelsFile)[name]!.quad!;
      final path = '${temp.path}/shadow_$name';
      File('${source.path}/$name').copySync(path);
      final original = unevenness(
        decode(await render(path, quad, PageFilter.original)),
      );
      final enhanced = unevenness(
        decode(await render(path, quad, PageFilter.enhancedColor)),
      );
      expect(enhanced, lessThan(original * 0.5));
    }, skip: skip);
  });
}

Future<String> writeScene(String name, {double shadow = 0}) async {
  final bmp = syntheticPageBmp(
    sceneWidth,
    sceneHeight,
    quad: sceneQuad,
    shadow: shadow,
  );
  final jpeg = await renderer.thumbnail(bmp, maxSide: sceneWidth);
  final path = '${temp.path}/$name';
  File(path).writeAsBytesSync(jpeg);
  return path;
}

Future<Uint8List> render(
  String path,
  Quad quad,
  PageFilter filter, {
  int rotation = 0,
  Map<String, double> params = const {},
  int maxLongSide = 0,
}) => renderer.render(
  path,
  quad,
  rotation,
  filter,
  params,
  maxLongSide: maxLongSide,
);

img.Image decode(Uint8List bytes) => img.decodeJpg(bytes)!;

/// Colour components in the JPEG frame header (package:image always gives 3).
int jpegComponents(Uint8List jpeg) {
  var i = 2;
  while (i + 9 < jpeg.length) {
    final marker = jpeg[i + 1];
    if (marker >= 0xc0 && marker <= 0xc2) return jpeg[i + 9];
    i += 2 + (jpeg[i + 2] << 8 | jpeg[i + 3]);
  }
  throw const FormatException('no SOF marker');
}

(int, int) naturalSize(Quad quad, int width, int height) {
  double edge(Point a, Point b) => math.sqrt(
    math.pow((a.x - b.x) * width, 2) + math.pow((a.y - b.y) * height, 2),
  );
  final w = math.max(
    edge(quad.topLeft, quad.topRight),
    edge(quad.bottomLeft, quad.bottomRight),
  );
  final h = math.max(
    edge(quad.topLeft, quad.bottomLeft),
    edge(quad.topRight, quad.bottomRight),
  );
  return (w.round(), h.round());
}

void expectSize(img.Image image, (int, int) size) {
  final (w, h) = size;
  expect((image.width - w).abs(), lessThanOrEqualTo(1), reason: 'width');
  expect((image.height - h).abs(), lessThanOrEqualTo(1), reason: 'height');
}

Point rotate(Point p, int degrees) => switch (degrees) {
  90 => (x: 1 - p.y, y: p.x),
  180 => (x: 1 - p.x, y: 1 - p.y),
  270 => (x: p.y, y: 1 - p.x),
  _ => p,
};

double luma(img.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return image.numChannels == 1
      ? p.r.toDouble()
      : 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
}

double meanLumaAt(img.Image image, Point at, {int radius = 8}) {
  final cx = (at.x * image.width).round(), cy = (at.y * image.height).round();
  var sum = 0.0, n = 0;
  for (var y = cy - radius; y <= cy + radius; y++) {
    for (var x = cx - radius; x <= cx + radius; x++) {
      sum += luma(image, x, y);
      n++;
    }
  }
  return sum / n;
}

double meanAbsDiff(img.Image a, img.Image b) {
  var sum = 0.0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      sum += (luma(a, x, y) - luma(b, x, y)).abs();
    }
  }
  return sum / (a.width * a.height);
}

/// Share of pixels that are neither near black nor near white.
double midtoneFraction(img.Image image) {
  var mid = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final v = luma(image, x, y);
      if (v > 32 && v < 223) mid++;
    }
  }
  return mid / (image.width * image.height);
}

/// Spread of the paper brightness: standard deviation, across an 8x6 grid
/// inside a 5% margin, of each block's 90th-percentile luma (text-proof).
double unevenness(img.Image image) {
  const cols = 8, rows = 6;
  final x0 = image.width * 0.05, y0 = image.height * 0.05;
  final bw = image.width * 0.9 / cols, bh = image.height * 0.9 / rows;
  final levels = <double>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final values = [
        for (
          var y = (y0 + r * bh).round();
          y < (y0 + (r + 1) * bh).round();
          y++
        )
          for (
            var x = (x0 + c * bw).round();
            x < (x0 + (c + 1) * bw).round();
            x++
          )
            luma(image, x, y),
      ]..sort();
      levels.add(values[(values.length * 0.9).floor()]);
    }
  }
  final mean = levels.reduce((a, b) => a + b) / levels.length;
  final variance =
      levels.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
      levels.length;
  return math.sqrt(variance);
}
