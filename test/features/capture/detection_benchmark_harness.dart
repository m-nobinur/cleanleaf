import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/features/capture/domain/quad_detector.dart';
import 'package:image/image.dart' as img;

const defaultFixturesPath =
    '/Users/nobin/Work/beenwise/cleanleaf/.local/fixtures/detection';
const hitToleranceOfDiagonal = 0.02;
const overallGate = 0.90;
const lowContrastGate = 0.75;
const noDocumentTag = 'no-document';
const lowContrastTag = 'low-contrast';

typedef Label = ({Quad? quad, Set<String> tags});

Directory fixturesDir() => Directory(
  Platform.environment['CLEANLEAF_FIXTURES'] ?? defaultFixturesPath,
);

/// Null when the directory is usable, otherwise why the benchmark can't run.
String? fixturesProblem(Directory dir) {
  final labels = File('${dir.path}/labels.json');
  if (!dir.existsSync() || !labels.existsSync()) {
    return 'no fixtures at ${dir.path}';
  }
  if (loadLabels(labels).isEmpty) return 'labels.json in ${dir.path} is empty';
  return null;
}

Map<String, Label> loadLabels(File file) {
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final MapEntry(:key, :value) in json.entries)
      key: _parseLabel(value as Map<String, dynamic>),
  };
}

Label _parseLabel(Map<String, dynamic> json) {
  final corners = json['corners'] as List<dynamic>?;
  final tags = {...(json['tags'] as List<dynamic>? ?? []).cast<String>()};
  if (corners == null) return (quad: null, tags: {...tags, noDocumentTag});
  final p = [
    for (final c in corners)
      (
        x: ((c as List<dynamic>)[0] as num).toDouble(),
        y: (c[1] as num).toDouble(),
      ),
  ];
  if (p.length != 4) throw FormatException('expected 4 corners, got $p');
  return (
    quad: (topLeft: p[0], topRight: p[1], bottomRight: p[2], bottomLeft: p[3]),
    tags: tags,
  );
}

bool isHit(
  Quad? expected,
  Quad? actual, {
  required int width,
  required int height,
}) {
  if (expected == null) return actual == null;
  if (actual == null) return false;
  final limit =
      hitToleranceOfDiagonal * math.sqrt(width * width + height * height);
  final want = expected.corners;
  final got = actual.corners;
  // Any cyclic start counts: "top-left" is ambiguous for a page rotated ~45°.
  bool matchesFrom(int shift) {
    for (var i = 0; i < 4; i++) {
      final g = got[(i + shift) % 4];
      final dx = (g.x - want[i].x) * width;
      final dy = (g.y - want[i].y) * height;
      if (math.sqrt(dx * dx + dy * dy) > limit) return false;
    }
    return true;
  }

  return List.generate(4, (s) => s).any(matchesFrom);
}

class BenchmarkReport {
  BenchmarkReport(this.overall, this.byTag, this.misses);

  final ({int hits, int total}) overall;
  final Map<String, ({int hits, int total})> byTag;
  final List<String> misses;

  static double rate(({int hits, int total}) r) =>
      r.total == 0 ? 0 : r.hits / r.total;

  /// Fails when there is no low-contrast sample, since the gate can't be shown met.
  bool get passesGate {
    final low = byTag[lowContrastTag];
    return rate(overall) >= overallGate &&
        low != null &&
        rate(low) >= lowContrastGate;
  }

  String format() {
    String line(String name, ({int hits, int total}) r) =>
        '${name.padRight(14)} ${r.hits}/${r.total}  ${(rate(r) * 100).toStringAsFixed(1)}%';
    return [
      line('overall', overall),
      for (final tag in byTag.keys.toList()..sort()) line(tag, byTag[tag]!),
      if (misses.isNotEmpty) 'misses: ${misses.join(', ')}',
      'gate: overall >= ${overallGate * 100}%, $lowContrastTag >= ${lowContrastGate * 100}% '
          '-> ${passesGate ? 'PASS' : 'FAIL'}',
    ].join('\n');
  }
}

Future<BenchmarkReport> runBenchmark(
  Directory dir,
  QuadDetector detector,
) async {
  final labels = loadLabels(File('${dir.path}/labels.json'));
  var hits = 0;
  final tagCounts = <String, ({int hits, int total})>{};
  final misses = <String>[];
  for (final MapEntry(:key, :value) in labels.entries) {
    final bytes = File('${dir.path}/$key').readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) throw StateError('cannot decode $key');
    final found = await detector.detect(bytes);
    final hit = isHit(
      value.quad,
      found,
      width: image.width,
      height: image.height,
    );
    if (hit) {
      hits++;
    } else {
      misses.add(key);
    }
    for (final tag in value.tags) {
      final c = tagCounts[tag] ?? (hits: 0, total: 0);
      tagCounts[tag] = (hits: c.hits + (hit ? 1 : 0), total: c.total + 1);
    }
  }
  return BenchmarkReport((hits: hits, total: labels.length), tagCounts, misses);
}
