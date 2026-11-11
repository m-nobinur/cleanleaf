import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';
import 'file_store.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(driftDatabase(name: 'cleanleaf'));
  ref.onDispose(db.close);
  return db;
});

final fileStoreProvider = Provider<FileStore>((ref) {
  Future<Directory>? root;
  return FileStore(() => root ??= getApplicationSupportDirectory());
});
