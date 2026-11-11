import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/spacing.dart';
import '../../../core/widgets/modal_close_button.dart';
import '../domain/scan_engine.dart';
import 'scan_engine_providers.dart';

Future<void> showScanEngineDialog(BuildContext context) => showShadDialog<void>(
  context: context,
  barrierLabel: 'Dismiss',
  builder: (_) => const ShadDialog(
    title: ModalTitle('Scanner engine'),
    closeIcon: ModalCloseButton(),
    closeIconPosition: modalClosePosition,
    child: Padding(
      padding: EdgeInsets.only(top: Spacing.md),
      child: ScanEnginePicker(),
    ),
  ),
);

class ScanEnginePicker extends ConsumerWidget {
  const ScanEnginePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(scanEngineProvider).value;
    final available = ref.watch(googleScannerAvailableProvider);
    if (engine == null || available.isLoading) {
      return const SizedBox(height: 48);
    }
    final googleAvailable = available.value ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // shadcn's vertical Wrap leaves items unbounded in width, so long
        // sublabels ran off the dialog; bound each item to the dialog width.
        LayoutBuilder(
          builder: (context, box) {
            Widget bounded(Widget radio) =>
                SizedBox(width: box.maxWidth, child: radio);
            return ShadRadioGroup<ScanEngine>(
              initialValue: googleAvailable ? engine : ScanEngine.cleanleaf,
              onChanged: (value) {
                if (value != null) {
                  ref.read(scanEngineProvider.notifier).select(value);
                }
              },
              spacing: Spacing.lg,
              items: [
                bounded(
                  const ShadRadio(
                    value: ScanEngine.cleanleaf,
                    label: Text('Cleanleaf'),
                    sublabel: Text('On this device, fully private. Default.'),
                  ),
                ),
                if (googleAvailable)
                  bounded(
                    const ShadRadio(
                      value: ScanEngine.googleMlKit,
                      label: Text('Google ML Kit'),
                      sublabel: Text(
                        'Runs in Google Play services, which downloads it on '
                        'first use.',
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (!googleAvailable) ...[
          const SizedBox(height: Spacing.md),
          Text(
            'Google ML Kit needs Google Play services, which this device '
            "doesn't have.",
            style: ShadTheme.of(context).textTheme.muted,
          ),
        ],
      ],
    );
  }
}
