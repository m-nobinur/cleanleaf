import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';

final autoCaptureSettingProvider =
    AsyncNotifierProvider<AutoCaptureSetting, bool>(AutoCaptureSetting.new);

/// Whether the camera shoots on its own once a page holds still; on by default.
class AutoCaptureSetting extends AsyncNotifier<bool> {
  static const _key = 'autoCapture';

  @override
  Future<bool> build() async =>
      await ref.watch(settingsStoreProvider).read(_key) != 'off';

  Future<void> set(bool on) async {
    state = AsyncData(on);
    await ref.read(settingsStoreProvider).write(_key, on ? 'on' : 'off');
  }
}
