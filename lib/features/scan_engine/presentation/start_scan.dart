import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/metrics/scan_metrics.dart';
import '../../../core/router/app_routes.dart';
import '../domain/scan_engine.dart';
import 'scan_engine_providers.dart';

var _googleScanRunning = false;

/// The Scan button: the one place that routes by the selected engine.
Future<void> startScan(BuildContext context, WidgetRef ref) async {
  if (_googleScanRunning) return;
  final engine = await ref.read(scanEngineProvider.future);
  if (!context.mounted) return;
  ScanMetrics.start(engine.name);
  if (engine == ScanEngine.cleanleaf) {
    await context.push(AppRoutes.capture);
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
    await context.push(AppRoutes.capture);
  } finally {
    _googleScanRunning = false;
  }
}
