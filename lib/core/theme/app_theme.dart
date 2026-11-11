import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Brand palette: ink, mist, leaf (primary actions), ember (sparing highlights).
abstract final class Brand {
  static const ink = Color(0xFF111111);
  static const mist = Color(0xFFE7E7E7);
  static const leaf = Color(0xFF0A8A5A);
  static const ember = Color(0xFFEC5C1D);
}

extension BrandColors on ShadColorScheme {
  Color get highlight => custom['highlight']!;
}

abstract final class AppTheme {
  static const monoFamily = 'JetBrainsMono';
  static const _radius = BorderRadius.all(Radius.circular(12));

  static final light = _theme(
    Brightness.light,
    const ShadColorScheme(
      background: Color(0xFFF4F4F4),
      foreground: Brand.ink,
      card: Color(0xFFFFFFFF),
      cardForeground: Brand.ink,
      popover: Color(0xFFFFFFFF),
      popoverForeground: Brand.ink,
      primary: Brand.leaf,
      primaryForeground: Color(0xFFFFFFFF),
      secondary: Brand.mist,
      secondaryForeground: Brand.ink,
      muted: Brand.mist,
      mutedForeground: Color(0xFF6B6B6B),
      accent: Brand.mist,
      accentForeground: Brand.ink,
      destructive: Color(0xFFD92D20),
      destructiveForeground: Color(0xFFFFFFFF),
      border: Color(0xFFDADADA),
      input: Color(0xFFDADADA),
      ring: Brand.leaf,
      selection: Color(0x330A8A5A),
      custom: {'highlight': Brand.ember},
    ),
  );

  static final dark = _theme(
    Brightness.dark,
    const ShadColorScheme(
      background: Brand.ink,
      foreground: Color(0xFFF4F4F4),
      card: Color(0xFF1B1B1B),
      cardForeground: Color(0xFFF4F4F4),
      popover: Color(0xFF1B1B1B),
      popoverForeground: Color(0xFFF4F4F4),
      primary: Brand.leaf,
      primaryForeground: Color(0xFFFFFFFF),
      secondary: Color(0xFF242424),
      secondaryForeground: Color(0xFFF4F4F4),
      muted: Color(0xFF242424),
      mutedForeground: Color(0xFF9E9E9E),
      accent: Color(0xFF242424),
      accentForeground: Color(0xFFF4F4F4),
      destructive: Color(0xFFF04438),
      destructiveForeground: Color(0xFFFFFFFF),
      border: Color(0xFF2E2E2E),
      input: Color(0xFF2E2E2E),
      ring: Brand.leaf,
      selection: Color(0x550A8A5A),
      custom: {'highlight': Brand.ember},
    ),
  );

  static ShadThemeData _theme(Brightness brightness, ShadColorScheme colors) {
    final base = ShadTextTheme();
    TextStyle mono(TextStyle s, FontWeight w) =>
        s.copyWith(fontFamily: monoFamily, fontWeight: w, letterSpacing: -0.5);
    return ShadThemeData(
      brightness: brightness,
      colorScheme: colors,
      radius: _radius,
      textTheme: base.copyWith(
        h1Large: mono(base.h1Large, FontWeight.w600),
        h1: mono(base.h1, FontWeight.w600),
        h2: mono(base.h2, FontWeight.w500),
        h3: mono(base.h3, FontWeight.w500),
        h4: mono(base.h4, FontWeight.w500),
      ),
    );
  }
}
