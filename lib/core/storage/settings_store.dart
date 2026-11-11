import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ids.dart';

/// App settings kept as one small JSON object in `settings.json`.
class SettingsStore {
  SettingsStore(this._root);

  final Future<Directory> Function() _root;

  Future<File> get _file async =>
      File(p.join((await _root()).path, 'settings.json'));

  Future<String?> read(String key) async => (await _load())[key] as String?;

  /// Atomic: the file is replaced only once the new content is on disk.
  Future<void> write(String key, String value) async {
    final values = await _load()
      ..[key] = value;
    final file = await _file;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.${newId()}.tmp');
    await temp.writeAsString(jsonEncode(values), flush: true);
    await temp.rename(file.path);
  }

  // A missing or corrupt file means defaults, never a crash.
  Future<Map<String, Object?>> _load() async {
    try {
      final decoded = jsonDecode(await (await _file).readAsString());
      return decoded is Map<String, Object?> ? decoded : {};
    } on Object {
      return {};
    }
  }
}
