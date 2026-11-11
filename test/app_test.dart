import 'package:cleanleaf/app.dart';
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
