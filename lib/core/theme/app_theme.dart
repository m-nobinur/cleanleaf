import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'radii.dart';

/// Brand palette: ink, mist, leaf (primary actions), ember (sparing highlights).
abstract final class Brand {
  static const ink = Color(0xFF111111);
  static const mist = Color(0xFFE7E7E7);
  static const leaf = Color(0xFF0A8A5A);
  static const ember = Color(0xFFEC5C1D);
}

extension BrandColors on ShadColorScheme {
  Color get highlight => custom['highlight']!;
  Color get hairline => custom['hairline']!;
  Color get badge => custom['badge']!;
  Color get tileLeaf => custom['tileLeaf']!;
  Color get tileEmber => custom['tileEmber']!;
  Color get tileMist => custom['tileMist']!;
  Color get tileInk => custom['tileInk']!;
  Color get onTileInk => custom['onTileInk']!;
  Color get nav => custom['nav']!;
  Color get onNav => custom['onNav']!;
  Color get navSelected => custom['navSelected']!;
  Color get onNavSelected => custom['onNavSelected']!;
}

/// Named v2 text styles; colour comes from the surrounding DefaultTextStyle.
extension AppText on ShadTextTheme {
  TextStyle get greeting => _geist(36, -0.015, height: 1.08);
  TextStyle get tileTitle => _geist(20, -0.01);
  TextStyle get caption =>
      p.copyWith(fontSize: 13, fontWeight: FontWeight.w400, height: 1.3);
  TextStyle get monoLabel => _mono(11, FontWeight.w500, 0.06);
  TextStyle get monoMeta => _mono(12, FontWeight.w400, 0);

  // Flutter letterSpacing is in logical pixels, so tracking is scaled by size.
  TextStyle _geist(double size, double tracking, {double? height}) =>
      p.copyWith(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: tracking * size,
        height: height,
      );

  TextStyle _mono(double size, FontWeight weight, double tracking) =>
      p.copyWith(
        fontFamily: AppTheme.monoFamily,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: tracking * size,
        height: 1.3,
      );
}

abstract final class AppTheme {
  static const monoFamily = 'JetBrainsMono';
  static const _radius = BorderRadius.all(Radius.circular(Radii.sm));

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
      custom: {
        'highlight': Brand.ember,
        'hairline': Color(0xFFDEDEDE),
        'badge': Color(0xFFFFFFFF),
        'tileLeaf': Color(0xFFDDEFE6),
        'tileEmber': Color(0xFFFBE4D8),
        'tileMist': Color(0xFFFFFFFF),
        'tileInk': Brand.ink,
        'onTileInk': Brand.mist,
        'nav': Brand.ink,
        'onNav': Brand.mist,
        'navSelected': Color(0xFFFFFFFF),
        'onNavSelected': Brand.ink,
      },
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
      custom: {
        'highlight': Brand.ember,
        'hairline': Color(0xFF2E2E2E),
        'badge': Color(0xFF242424),
        // Leaf at 18% and ember at 15% over ink, pre-blended to opaque.
        'tileLeaf': Color(0xFF10271E),
        'tileEmber': Color(0xFF321C13),
        'tileMist': Color(0xFF1B1B1B),
        'tileInk': Color(0xFFF4F4F4),
        'onTileInk': Brand.ink,
        'nav': Color(0xFF1B1B1B),
        'onNav': Color(0xFF9E9E9E),
        'navSelected': Color(0xFFF4F4F4),
        'onNavSelected': Brand.ink,
      },
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
