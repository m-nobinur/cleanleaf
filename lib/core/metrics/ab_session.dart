import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Engine A/B recorder (T-020), on only in `--dart-define=CLEANLEAF_AB=1`
/// builds: scan events go to `events.jsonl` and page files are copied next to
/// it, for `adb pull`. Failures are logged and never reach the caller.
class AbSession {
  AbSession(this._dir, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  // String, not bool.fromEnvironment: that is true only for the value 'true'.
  static const enabled = String.fromEnvironment('CLEANLEAF_AB') == '1';

  /// Set once in `main` when [enabled].
  static AbSession? current;

  final Future<Directory> Function() _dir;
  final DateTime Function() _now;
  Future<void> _queue = Future.value();

  Future<void> event(String name, Map<String, Object?> fields) {
    final t = _now().millisecondsSinceEpoch;
    return _enqueue((dir) => _append(dir, t, name, fields));
  }

  /// Copies [source] (skipped when it resolves to null) as [fileName] and logs
  /// [name] stamped with the time of this call, not of the copy.
  Future<void> copy(
    String name,
    String fileName,
    Future<File?> Function() source,
    Map<String, Object?> fields,
  ) {
    final t = _now().millisecondsSinceEpoch;
    return _enqueue((dir) async {
      final file = await source();
      if (file == null) return;
      await file.copy(p.join(dir.path, fileName));
      await _append(dir, t, name, {...fields, 'file': fileName});
    });
  }

  Future<void> _append(
    Directory dir,
    int t,
    String name,
    Map<String, Object?> fields,
  ) => File(p.join(dir.path, 'events.jsonl')).writeAsString(
    '${jsonEncode({'t': t, 'event': name, ...fields})}\n',
    mode: FileMode.append,
    flush: true,
  );

  // Serialized so events.jsonl keeps call order.
  Future<void> _enqueue(Future<void> Function(Directory dir) job) =>
      _queue = _queue.then((_) async {
        try {
          final dir = await _dir();
          await dir.create(recursive: true);
          await job(dir);
        } on Object catch (e) {
          debugPrint('CLMETRIC ab_error $e');
        }
      });
}
