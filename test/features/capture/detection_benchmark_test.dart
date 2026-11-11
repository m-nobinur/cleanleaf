// The benchmark prints its report to the test log.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/features/capture/domain/quad_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'detection_benchmark_harness.dart';

/// Wire the detector under test here (T-005 / T-018 replace this null).
final QuadDetector? detectorUnderTest = null;

/// Finds the bounding box of near-white pixels; enough for synthetic rectangles.
class _BrightBoxDetector implements QuadDetector {
  @override
  Future<Quad?> detect(Uint8List encodedImage) async {
    final image = img.decodeImage(encodedImage)!;
    var minX = image.width, minY = image.height, maxX = -1, maxY = -1;
    for (final p in image) {
      if (p.r > 225) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
    }
    if (maxX < 0 ||
        (maxX - minX) * (maxY - minY) < image.width * image.height * 0.05) {
      return null;
    }
    Point at(int x, int y) => (x: x / image.width, y: y / image.height);
    return (
      topLeft: at(minX, minY),
      topRight: at(maxX, minY),
      bottomRight: at(maxX, maxY),
      bottomLeft: at(minX, maxY),
    );
  }
}

class _NeverDetector implements QuadDetector {
  @override
  Future<Quad?> detect(Uint8List encodedImage) async => null;
}

Directory _writeSyntheticFixtures() {
  final dir = Directory.systemTemp.createTempSync('cleanleaf_fixtures_');
  final labels = <String, Object>{};
  void add(
    String name,
    int background, {
    List<int>? rect,
    List<String> tags = const [],
  }) {
    const w = 200, h = 150;
    final image = img.Image(width: w, height: h)
      ..clear(img.ColorRgb8(background, background, background));
    List<List<double>>? corners;
    if (rect != null) {
      final [x1, y1, x2, y2] = rect;
      img.fillRect(
        image,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: img.ColorRgb8(250, 250, 250),
      );
      corners = [
        [x1 / w, y1 / h],
        [x2 / w, y1 / h],
        [x2 / w, y2 / h],
        [x1 / w, y2 / h],
      ];
    }
    File('${dir.path}/$name').writeAsBytesSync(img.encodePng(image));
    labels[name] = {'corners': corners, 'tags': tags};
  }

  add('f001.png', 40, rect: [30, 20, 170, 130], tags: ['dark']);
  add(
    'f002.png',
    200,
    rect: [30, 20, 170, 130],
    tags: [lowContrastTag, 'light'],
  );
  add('f003.png', 120, rect: [50, 40, 150, 110], tags: ['shadow']);
  add('f004.png', 90);
  add('f005.png', 10);
  File('${dir.path}/labels.json').writeAsStringSync(jsonEncode(labels));
  return dir;
}

void main() {
  group('harness', () {
    late Directory fixtures;
    setUpAll(() => fixtures = _writeSyntheticFixtures());
    tearDownAll(() => fixtures.deleteSync(recursive: true));

    test('a working detector passes the gate with per-tag rates', () async {
      final report = await runBenchmark(fixtures, _BrightBoxDetector());
      expect(report.misses, isEmpty);
      expect(report.overall, (hits: 5, total: 5));
      expect(report.byTag[lowContrastTag], (hits: 1, total: 1));
      expect(report.byTag[noDocumentTag], (hits: 2, total: 2));
      expect(report.passesGate, isTrue);
    });

    test('a detector that never finds a page fails the gate', () async {
      final report = await runBenchmark(fixtures, _NeverDetector());
      expect(report.overall, (hits: 2, total: 5));
      expect(report.byTag[lowContrastTag], (hits: 0, total: 1));
      expect(report.misses, ['f001.png', 'f002.png', 'f003.png']);
      expect(report.passesGate, isFalse);
    });

    test('hit tolerance is 2% of the diagonal per corner', () {
      Quad square(double dx) => (
        topLeft: (x: 0.2 + dx, y: 0.2),
        topRight: (x: 0.8, y: 0.2),
        bottomRight: (x: 0.8, y: 0.8),
        bottomLeft: (x: 0.2, y: 0.8),
      );
      // 100x100 image: diagonal 141.4 px, limit 2.83 px.
      expect(isHit(square(0), square(0.027), width: 100, height: 100), isTrue);
      expect(isHit(square(0), square(0.03), width: 100, height: 100), isFalse);
      expect(isHit(null, null, width: 100, height: 100), isTrue);
      expect(isHit(null, square(0), width: 100, height: 100), isFalse);
      expect(isHit(square(0), null, width: 100, height: 100), isFalse);
    });

    test(
      'missing or empty fixture dirs report a problem instead of failing',
      () {
        final empty = Directory.systemTemp.createTempSync('cleanleaf_empty_');
        addTearDown(() => empty.deleteSync(recursive: true));
        expect(fixturesProblem(Directory('${empty.path}/nope')), isNotNull);
        expect(fixturesProblem(empty), isNotNull);
        File('${empty.path}/labels.json').writeAsStringSync('{}');
        expect(fixturesProblem(empty), isNotNull);
        expect(fixturesProblem(fixtures), isNull);
      },
    );
  });

  final dir = fixturesDir();
  final skipReason =
      fixturesProblem(dir) ??
      (detectorUnderTest == null ? 'no detector wired yet' : null);
  test(
    'detection benchmark meets the gate',
    () async {
      final report = await runBenchmark(dir, detectorUnderTest!);
      print(report.format());
      expect(report.passesGate, isTrue);
    },
    tags: 'benchmark',
    skip: skipReason,
  );
}
