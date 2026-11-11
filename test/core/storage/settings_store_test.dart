import 'dart:io';

import 'package:cleanleaf/core/storage/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a real store round-trips through settings.json', () async {
    final dir = await Directory.systemTemp.createTemp('settings');
    addTearDown(() => dir.delete(recursive: true));
    final real = SettingsStore(() async => dir);
    expect(await real.read('scanEngine'), isNull);
    await real.write('scanEngine', 'googleMlKit');
    expect(
      await SettingsStore(() async => dir).read('scanEngine'),
      'googleMlKit',
    );
    File('${dir.path}/settings.json').writeAsStringSync('{not json');
    expect(await real.read('scanEngine'), isNull);
  });
}
