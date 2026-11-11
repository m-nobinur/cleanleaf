import 'package:cleanleaf/core/storage/settings_store.dart';
import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:cleanleaf/features/library/presentation/settings_sheet.dart';
import 'package:cleanleaf/features/scan_engine/presentation/scan_engine_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FakeSettingsStore implements SettingsStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  late FakeSettingsStore store;

  setUp(() => store = FakeSettingsStore());

  Future<void> openPicker(
    WidgetTester tester, {
    required bool googleAvailable,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // A new scope each pump, so the engine is re-read from the store.
        key: UniqueKey(),
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          googleScannerAvailableProvider.overrideWith(
            (ref) async => googleAvailable,
          ),
        ],
        child: ShadApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => ShadButton(
              onPressed: () => showSettingsSheet(context),
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scanner engine'));
    await tester.pumpAndSettle();
  }

  bool isSelected(WidgetTester tester, String label) =>
      tester
          .widget<ShadRadio<Object?>>(
            find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is ShadRadio),
            ),
          )
          .value ==
      tester
          .widget<ShadRadioGroup<Object?>>(
            find.byWidgetPredicate((w) => w is ShadRadioGroup),
          )
          .initialValue;

  testWidgets('defaults to Cleanleaf, toggles to Google and persists it', (
    tester,
  ) async {
    await openPicker(tester, googleAvailable: true);
    expect(isSelected(tester, 'Cleanleaf'), isTrue);

    await tester.tap(find.text('Google ML Kit'));
    await tester.pumpAndSettle();
    expect(store.values['scanEngine'], 'googleMlKit');

    await openPicker(tester, googleAvailable: true);
    expect(isSelected(tester, 'Google ML Kit'), isTrue);

    await tester.tap(find.text('Cleanleaf'));
    await tester.pumpAndSettle();
    expect(store.values['scanEngine'], 'cleanleaf');
  });

  testWidgets('hides Google with a reason when Play Services is missing', (
    tester,
  ) async {
    await openPicker(tester, googleAvailable: false);
    expect(find.text('Cleanleaf'), findsOneWidget);
    expect(find.text('Google ML Kit'), findsNothing);
    expect(find.textContaining('needs Google Play services'), findsOneWidget);
  });
}
