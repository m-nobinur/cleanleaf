import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/bento_tile.dart';
import '../../../core/widgets/corner_brackets.dart';
import '../domain/scan_mode.dart';

final lastScanModeProvider = AsyncNotifierProvider<LastScanMode, ScanMode>(
  LastScanMode.new,
);

class LastScanMode extends AsyncNotifier<ScanMode> {
  static const _key = 'lastScanMode';

  @override
  Future<ScanMode> build() async =>
      ScanMode.parse(await ref.watch(settingsStoreProvider).read(_key));

  Future<void> set(ScanMode mode) async {
    state = AsyncData(mode);
    await ref.read(settingsStoreProvider).write(_key, mode.name);
  }
}

extension ScanModeLabels on ScanMode {
  String get label => switch (this) {
    ScanMode.document => 'Document',
    ScanMode.idCard => 'ID card',
    ScanMode.passport => 'Passport',
    ScanMode.receipt => 'Receipt',
    ScanMode.book => 'Book',
    ScanMode.qrCode => 'QR code',
    ScanMode.barcode => 'Barcode',
  };

  String get caption => switch (this) {
    ScanMode.document => 'Pages, letters, forms',
    ScanMode.idCard => 'Snaps to card size',
    ScanMode.passport => 'Photo page, snaps to size',
    ScanMode.receipt => 'Long, narrow slips',
    ScanMode.book => 'Two-page spread as one page',
    ScanMode.qrCode => 'Read links and text',
    ScanMode.barcode => 'Read product codes',
  };

  IconData get icon => switch (this) {
    ScanMode.document => LucideIcons.fileText,
    ScanMode.idCard => LucideIcons.idCard,
    ScanMode.passport => LucideIcons.bookUser,
    ScanMode.receipt => LucideIcons.receipt,
    ScanMode.book => LucideIcons.bookOpen,
    ScanMode.qrCode => LucideIcons.scanQrCode,
    ScanMode.barcode => LucideIcons.scanBarcode,
  };

  TileTone get tone => switch (this) {
    ScanMode.document => TileTone.leaf,
    ScanMode.idCard => TileTone.mist,
    ScanMode.passport => TileTone.mist,
    ScanMode.receipt => TileTone.ember,
    ScanMode.book => TileTone.mist,
    ScanMode.qrCode => TileTone.mist,
    ScanMode.barcode => TileTone.mist,
  };
}

Future<ScanMode?> showScanModeSheet(BuildContext context) =>
    showShadSheet<ScanMode>(
      context: context,
      barrierLabel: 'Dismiss',
      side: ShadSheetSide.bottom,
      builder: (_) => const ScanModeSheet(),
    );

class ScanModeSheet extends StatelessWidget {
  const ScanModeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadSheet(
      title: Row(
        children: [
          const BrandBadge(),
          const SizedBox(width: Spacing.md),
          Text('Scan', style: theme.textTheme.greeting.copyWith(fontSize: 28)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.lg),
        child: GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Without it the grid adds the status-bar inset as top padding.
          padding: EdgeInsets.zero,
          // A fixed height keeps all seven modes on one 360 dp screen.
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: Spacing.md,
            crossAxisSpacing: Spacing.md,
            mainAxisExtent: 140,
          ),
          children: [
            for (final mode in ScanMode.values)
              BentoTile(
                key: ValueKey(mode),
                tone: mode.tone,
                icon: mode.icon,
                title: mode.label,
                caption: mode.caption,
                badge: mode.isAvailable ? null : 'SOON',
                onTap: mode.isAvailable
                    ? () => Navigator.of(context).pop(mode)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
