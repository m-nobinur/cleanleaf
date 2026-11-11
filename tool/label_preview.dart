// Usage: dart run tool/label_preview.dart [--dir D] [--out O] [--proposals P.json] [--only a.jpg,b.jpg]
// Per image: <name>.overlay.png (quad drawn), <name>.c1..c4.png (3x zoomed corner
// crops with a pixel grid and absolute pixel coordinates) and <name>.corners.png
// (the four crops in one sheet). Proposals use the labels.json shape (corners
// only) and are drawn red over the labelled quad in cyan, to refine by eye.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const defaultDir =
    '/Users/nobin/Work/beenwise/cleanleaf/.local/fixtures/detection';
const overlayLongSide = 1024;
const cropRadius = 48; // source px each side of the corner
const zoom = 3;
const captionHeight = 20;
const cornerNames = ['TL', 'TR', 'BR', 'BL'];

typedef Corners = List<List<double>>;

void main(List<String> args) {
  final opts = _parse(args);
  final dir =
      opts['dir'] ?? Platform.environment['CLEANLEAF_FIXTURES'] ?? defaultDir;
  final out = Directory(opts['out'] ?? '$dir/../detection-preview')
    ..createSync(recursive: true);
  final labels = _read(opts['labels'] ?? '$dir/labels.json');
  final proposals = opts['proposals'] == null
      ? <String, Corners?>{}
      : _read(opts['proposals']!);
  final names =
      opts['only']?.split(',') ?? {...labels.keys, ...proposals.keys}.toList()
        ..sort();

  for (final name in names) {
    final file = File('$dir/$name');
    final image = img.decodeImage(file.readAsBytesSync());
    if (image == null) {
      stderr.writeln('skip (undecodable): $name');
      continue;
    }
    final labelled = labels[name];
    final proposed = proposals[name];
    _writeOverlay(
      out,
      name,
      image,
      labelled,
      proposed,
      hasLabel: labels.containsKey(name),
    );
    final primary = proposed ?? labelled;
    if (primary == null) continue;
    final crops = <img.Image>[];
    for (var i = 0; i < 4; i++) {
      final crop = _cornerCrop(
        image,
        i,
        primary,
        proposed == null ? null : labelled,
      );
      img.encodePngFile('${out.path}/$name.c${i + 1}.png', crop);
      crops.add(crop);
    }
    final sheet = img.Image(
      width: crops[0].width * 2,
      height: crops[0].height * 2,
    );
    for (var i = 0; i < 4; i++) {
      img.compositeImage(
        sheet,
        crops[i],
        dstX: (i % 2) * crops[0].width,
        dstY: (i ~/ 2) * crops[0].height,
      );
    }
    img.encodePngFile('${out.path}/$name.corners.png', sheet);
  }
  stdout.writeln('wrote previews for ${names.length} image(s) to ${out.path}');
}

Map<String, String> _parse(List<String> args) {
  final opts = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    if (!args[i].startsWith('--')) throw ArgumentError('unexpected ${args[i]}');
    opts[args[i].substring(2)] = args[i + 1];
  }
  return opts;
}

Map<String, Corners?> _read(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final MapEntry(:key, :value) in json.entries)
      key: ((value as Map<String, dynamic>)['corners'] as List<dynamic>?)
          ?.map(
            (c) =>
                (c as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
          )
          .toList(),
  };
}

void _writeOverlay(
  Directory out,
  String name,
  img.Image image,
  Corners? labelled,
  Corners? proposed, {
  required bool hasLabel,
}) {
  final scale = overlayLongSide / math.max(image.width, image.height);
  final small = img.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
  );
  void quad(Corners c, img.Color color, int thickness) {
    final p = [
      for (final v in c)
        (x: (v[0] * small.width).round(), y: (v[1] * small.height).round()),
    ];
    for (var i = 0; i < 4; i++) {
      final a = p[i], b = p[(i + 1) % 4];
      img.drawLine(
        small,
        x1: a.x,
        y1: a.y,
        x2: b.x,
        y2: b.y,
        color: color,
        thickness: thickness,
      );
    }
    for (var i = 0; i < 4; i++) {
      img.drawString(
        small,
        '${i + 1}',
        font: img.arial24,
        x: p[i].x + 6,
        y: p[i].y + 6,
        color: color,
      );
    }
  }

  if (labelled != null) {
    quad(labelled, img.ColorRgb8(0, 255, 255), proposed == null ? 3 : 1);
  }
  if (proposed != null) quad(proposed, img.ColorRgb8(255, 40, 40), 3);
  if (labelled == null && proposed == null) {
    img.drawString(
      small,
      hasLabel ? 'NO DOCUMENT' : 'UNLABELED',
      font: img.arial48,
      x: 20,
      y: 20,
      color: img.ColorRgb8(255, 160, 0),
    );
  }
  img.encodePngFile('${out.path}/$name.overlay.png', small);
}

img.Image _cornerCrop(
  img.Image image,
  int index,
  Corners primary,
  Corners? other,
) {
  final cx = primary[index][0] * image.width,
      cy = primary[index][1] * image.height;
  final wx = cx.round() - cropRadius, wy = cy.round() - cropRadius;
  final side = cropRadius * 2 * zoom;
  final crop = img.Image(
    width: side,
    height: side + captionHeight,
    numChannels: 3,
  );
  img.fill(crop, color: img.ColorRgb8(0, 0, 0));
  for (var oy = 0; oy < side; oy++) {
    for (var ox = 0; ox < side; ox++) {
      final sx = wx + ox ~/ zoom, sy = wy + oy ~/ zoom;
      final inside =
          sx >= 0 && sy >= 0 && sx < image.width && sy < image.height;
      final p = inside ? image.getPixel(sx, sy) : null;
      crop.setPixelRgb(
        ox,
        oy + captionHeight,
        p?.r ?? 90,
        p?.g ?? 90,
        p?.b ?? 90,
      );
    }
  }
  final minor = img.ColorRgba8(0, 255, 255, 70),
      major = img.ColorRgba8(255, 255, 0, 150);
  for (var s = 0; s < cropRadius * 2; s++) {
    final isMajorX = (wx + s) % 32 == 0, isMajorY = (wy + s) % 32 == 0;
    if ((wx + s) % 8 == 0) {
      img.drawLine(
        crop,
        x1: s * zoom,
        y1: captionHeight,
        x2: s * zoom,
        y2: crop.height - 1,
        color: isMajorX ? major : minor,
      );
    }
    if ((wy + s) % 8 == 0) {
      img.drawLine(
        crop,
        x1: 0,
        y1: captionHeight + s * zoom,
        x2: side - 1,
        y2: captionHeight + s * zoom,
        color: isMajorY ? major : minor,
      );
    }
    if (isMajorX) {
      img.drawString(
        crop,
        '${wx + s}',
        font: img.arial14,
        x: s * zoom + 2,
        y: captionHeight + 2,
        color: img.ColorRgb8(255, 255, 0),
      );
    }
    if (isMajorY) {
      img.drawString(
        crop,
        '${wy + s}',
        font: img.arial14,
        x: 2,
        y: captionHeight + s * zoom + 2,
        color: img.ColorRgb8(255, 255, 0),
      );
    }
  }
  void cross(double px, double py, img.Color color) {
    final x = ((px - wx) * zoom).round(),
        y = captionHeight + ((py - wy) * zoom).round();
    img.drawLine(crop, x1: x - 12, y1: y, x2: x + 12, y2: y, color: color);
    img.drawLine(crop, x1: x, y1: y - 12, x2: x, y2: y + 12, color: color);
  }

  if (other != null) {
    final o = other[index];
    cross(o[0] * image.width, o[1] * image.height, img.ColorRgb8(0, 255, 255));
  }
  cross(cx, cy, img.ColorRgb8(255, 40, 40));
  img.drawString(
    crop,
    'c${index + 1} ${cornerNames[index]} x=${cx.toStringAsFixed(1)} y=${cy.toStringAsFixed(1)} of ${image.width}x${image.height}',
    font: img.arial14,
    x: 4,
    y: 2,
    color: img.ColorRgb8(255, 255, 255),
  );
  return crop;
}
