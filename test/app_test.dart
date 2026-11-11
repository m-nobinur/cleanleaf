import 'package:cleanleaf/app.dart';
import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/features/capture/data/capture_providers.dart';
import 'package:cleanleaf/features/library/data/library_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'features/capture/presentation/fake_camera.dart';
import 'features/library/presentation/fakes.dart';

void main() {
  testWidgets('opens on home and navigates to capture', (tester) async {
    tester.view.physicalSize = const Size(400, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(
            FakeDocumentRepository(),
          ),
          pageRepositoryProvider.overrideWithValue(FakePageRepository()),
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
          documentCameraProvider.overrideWithValue(FakeCamera()),
        ],
        child: const CleanleafApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scan, clean,\nshare.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quick-scan')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Take photo'), findsOneWidget);
  });
}
