import 'package:cleanleaf/app.dart';
import 'package:cleanleaf/core/storage/settings_store.dart';
import 'package:cleanleaf/core/storage/storage_providers.dart';
import 'package:cleanleaf/features/library/data/library_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'features/library/presentation/fakes.dart';

void main() {
  testWidgets('opens on library and navigates to capture', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(
            FakeDocumentRepository(),
          ),
          pageRepositoryProvider.overrideWithValue(FakePageRepository()),
          settingsStoreProvider.overrideWithValue(_MemorySettingsStore()),
        ],
        child: const CleanleafApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsOneWidget);

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Capture'), findsOneWidget);
  });
}

class _MemorySettingsStore implements SettingsStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
