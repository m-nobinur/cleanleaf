import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/geometry/quad.dart';
import '../../../core/metrics/scan_metrics.dart';
import '../../library/domain/default_title.dart';
import '../../library/domain/document_page.dart';
import '../../library/domain/document_repository.dart';
import '../../library/domain/page_repository.dart';
import '../domain/scan_mode.dart';
import '../domain/scan_mode_presets.dart';

/// Stores a camera still as the original of a new one-page document.
class CameraScan {
  CameraScan({
    required this.detect,
    required this.documents,
    required this.pages,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Full-resolution re-detection on the still; null when no page is found.
  final Future<Quad?> Function(String imagePath) detect;
  final DocumentRepository documents;
  final PageRepository pages;
  final DateTime Function() _now;

  /// [liveQuad] is the last live detection, used when the still has none;
  /// both are in the upright frame (decisions.md D-31, D-38).
  Future<DocumentPage> call(
    String stillPath, {
    required ScanMode mode,
    Quad? liveQuad,
  }) async {
    final still = File(stillPath);
    try {
      final watch = Stopwatch()..start();
      // A failed re-detection must not lose the shot.
      final detected = await detect(stillPath).catchError((Object _) => null);
      final corners = detected ?? liveQuad;
      final detectMs = watch.elapsedMilliseconds;
      final document = await documents.create(defaultDocumentTitle(_now()));
      try {
        final page = await pages.add(
          document.id,
          original: still.openRead(),
          detectedCorners: corners,
        );
        ScanMetrics.saved();
        final preset = page.copyWith(
          filter: mode.defaultFilter,
          // Snapping the full frame to a card shape would only stretch it.
          filterParams: corners == null ? const {} : mode.pageParams,
        );
        await pages.updateEdits(preset);
        debugPrint(
          'CLMETRIC capture_store detect_ms=$detectMs '
          'total_ms=${watch.elapsedMilliseconds}',
        );
        return preset;
      } catch (_) {
        await documents.delete(document.id);
        rethrow;
      }
    } finally {
      await _deleteQuietly(still);
    }
  }

  // Best effort: a leftover cache file must never undo a saved scan.
  Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Ignored; it is in the cache dir, which Android clears.
    }
  }
}
