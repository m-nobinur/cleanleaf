// Usage: dart run tool/upright_jpegs.dart <dir>
// package:image applies EXIF orientation on decode and writes none on encode, so
// a plain re-encode leaves upright pixels and no tag for every consumer.
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/upright_jpegs.dart <dir>');
    exit(64);
  }
  final files = Directory(args.single)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.jpg'));
  for (final file in files) {
    final image = img.decodeJpg(file.readAsBytesSync());
    if (image == null) {
      stderr.writeln('undecodable: ${file.path}');
      exit(65);
    }
    file.writeAsBytesSync(img.encodeJpg(image, quality: 92));
  }
}
