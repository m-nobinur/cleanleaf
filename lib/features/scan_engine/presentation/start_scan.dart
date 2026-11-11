import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/metrics/scan_metrics.dart';
import '../../../core/router/app_routes.dart';
import '../../capture/domain/scan_mode.dart';
import '../domain/scan_engine.dart';
import 'scan_engine_providers.dart';

var _googleScanRunning = false;

/// The Scan button: the one place that routes by the selected engine.
/// [mode] only applies to the Cleanleaf engine; Google picks its own.
Future<void> startScan(
  BuildContext context,
  WidgetRef ref, {
  ScanMode? mode,
}) async {
  if (_googleScanRunning) return;
  final capture = mode == null ? AppRoutes.capture : AppRoutes.captureIn(mode);
  final engine = await ref.read(scanEngineProvider.future);
  if (!context.mounted) return;
  ScanMetrics.start(engine.name);
  if (engine == ScanEngine.cleanleaf) {
    await context.push(capture);
    return;
  }
  _googleScanRunning = true;
  try {
    if (await ref.read(googleScanProvider)() != null) ScanMetrics.saved();
  } on Object {
    if (!context.mounted) return;
    ShadToaster.of(context).show(
      const ShadToast.destructive(
        title: Text('Google scanner unavailable, using Cleanleaf'),
      ),
    );
    ScanMetrics.start(ScanEngine.cleanleaf.name);
    await context.push(capture);
  } finally {
    _googleScanRunning = false;
  }
}
