import 'dart:io';

import 'package:cleanleaf/core/licenses/about_sheet.dart';
import 'package:cleanleaf/core/licenses/third_party_licenses.dart';
import 'package:cleanleaf/features/library/presentation/settings_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every notice file is bundled in assets/licenses', () {
    for (final notice in thirdPartyNotices) {
      for (final asset in notice.assets) {
        expect(File(asset).existsSync(), isTrue, reason: asset);
      }
    }
  });

  test('registered notices cover every listed component', () async {
    registerThirdPartyLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    for (final notice in thirdPartyNotices) {
      expect(
        entries.any(
          (LicenseEntry e) => e.packages.contains(notice.packages.single),
        ),
        isTrue,
        reason: notice.packages.single,
      );
    }
  });

  test('appVersion matches pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: $appVersion+'));
  });

  testWidgets('about sheet opens the open source licenses page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAboutSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Version $appVersion'), findsOneWidget);

    await tester.tap(find.text('Open source licenses'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('settings row opens the about sheet', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSettingsSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About & licenses'));
    await tester.pumpAndSettle();
    expect(find.text('Version $appVersion'), findsOneWidget);
  });
}
