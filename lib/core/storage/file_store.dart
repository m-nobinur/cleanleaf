import 'dart:io';

import 'package:path/path.dart' as p;

import 'ids.dart';

enum PageFile {
  original('original.jpg'),
  render('render.jpg'),
  thumb('thumb.jpg');

  const PageFile(this.fileName);

  final String fileName;
}

/// App-private files laid out as `docs/<docId>/<pageId>/<file>`.
/// Returned paths are relative to the root so they survive a moved data dir.
class FileStore {
  FileStore(this._root);

  final Future<Directory> Function() _root;

  Future<File> resolve(String relativePath) async =>
      File(p.join((await _root()).path, relativePath));

  /// Atomic: the target is replaced only once [bytes] is fully on disk.
  Future<String> writePageFile(
    String docId,
    String pageId,
    PageFile kind,
    Stream<List<int>> bytes,
  ) async {
    final relative = p.join('docs', docId, pageId, kind.fileName);
    final target = await resolve(relative);
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.${newId()}.tmp');
    try {
      final file = await temp.open(mode: FileMode.writeOnly);
      try {
        await for (final chunk in bytes) {
          await file.writeFrom(chunk);
        }
        // fsync before rename so a crash can't leave a renamed but empty file.
        await file.flush();
      } finally {
        await file.close();
      }
      await temp.rename(target.path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
    return relative;
  }

  Future<void> deletePage(String docId, String pageId) =>
      _deleteDir(p.join('docs', docId, pageId));

  Future<void> deleteDocument(String docId) =>
      _deleteDir(p.join('docs', docId));

  Future<void> _deleteDir(String relative) async {
    final dir = Directory(p.join((await _root()).path, relative));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
