import 'dart:ui';

import 'package:shadcn_ui/shadcn_ui.dart';

abstract final class AppTheme {
  static final light = ShadThemeData(
    brightness: Brightness.light,
    colorScheme: const ShadZincColorScheme.light(),
  );

  static final dark = ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: const ShadZincColorScheme.dark(),
  );
}
