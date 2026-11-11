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
  Color get tileLeafBadge => custom['tileLeafBadge']!;
  Color get tileLeafIcon => custom['tileLeafIcon']!;
  Color get tileLeafEdge => custom['tileLeafEdge']!;
  Color get tileEmberBadge => custom['tileEmberBadge']!;
  Color get tileEmberIcon => custom['tileEmberIcon']!;
  Color get tileEmberEdge => custom['tileEmberEdge']!;
  Color get tileMistBadge => custom['tileMistBadge']!;
  Color get tileMistIcon => custom['tileMistIcon']!;
  Color get tileInkBadge => custom['tileInkBadge']!;
  Color get tileInkIcon => custom['tileInkIcon']!;

  /// White wash over the top-left of tiles; transparent means flat tiles.
  Color get tileSheen => custom['tileSheen']!;

  /// Soft shadow under the primary scan button; transparent means none.
  Color get primaryGlow => custom['primaryGlow']!;
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
        'tileLeafBadge': Color(0xFFFFFFFF),
        'tileLeafIcon': Brand.ink,
        'tileLeafEdge': Color(0x00000000),
        'tileEmberBadge': Color(0xFFFFFFFF),
        'tileEmberIcon': Brand.ink,
        'tileEmberEdge': Color(0x00000000),
        'tileMistBadge': Color(0xFFFFFFFF),
        'tileMistIcon': Brand.ink,
        'tileInkBadge': Color(0xFFFFFFFF),
        'tileInkIcon': Brand.ink,
        'tileSheen': Color(0x00000000),
        'primaryGlow': Color(0x00000000),
        'nav': Brand.ink,
        'onNav': Brand.mist,
        'navSelected': Color(0xFFFFFFFF),
        'onNavSelected': Brand.ink,
      },
    ),
  );

  // T-034: compare dark variants on device with
  // --dart-define=CLEANLEAF_DARK_VARIANT=a|b; unset keeps the current theme.
  static const _darkVariant = String.fromEnvironment('CLEANLEAF_DARK_VARIANT');

  static final darkVariants = {
    '': _theme(Brightness.dark, _darkCurrent),
    'a': _theme(Brightness.dark, _darkInk),
    'b': _theme(Brightness.dark, _darkGraphite),
  };

  static final dark = darkVariants[_darkVariant] ?? darkVariants['']!;

  static ShadColorScheme _darkScheme({
    required Color background,
    required Color foreground,
    required Color card,
    required Color raised,
    required Color mutedForeground,
    required Color hairline,
    required Map<String, Color> custom,
  }) => ShadColorScheme(
    background: background,
    foreground: foreground,
    card: card,
    cardForeground: foreground,
    popover: card,
    popoverForeground: foreground,
    primary: Brand.leaf,
    primaryForeground: const Color(0xFFFFFFFF),
    secondary: raised,
    secondaryForeground: foreground,
    muted: raised,
    mutedForeground: mutedForeground,
    accent: raised,
    accentForeground: foreground,
    destructive: const Color(0xFFF04438),
    destructiveForeground: const Color(0xFFFFFFFF),
    border: hairline,
    input: hairline,
    ring: Brand.leaf,
    selection: const Color(0x550A8A5A),
    custom: {'highlight': Brand.ember, 'hairline': hairline, ...custom},
  );

  static final _darkCurrent = _darkScheme(
    background: Brand.ink,
    foreground: const Color(0xFFF4F4F4),
    card: const Color(0xFF1B1B1B),
    raised: const Color(0xFF242424),
    mutedForeground: const Color(0xFF9E9E9E),
    hairline: const Color(0xFF2E2E2E),
    custom: const {
      'badge': Color(0xFF242424),
      // Leaf at 18% and ember at 15% over ink, pre-blended to opaque.
      'tileLeaf': Color(0xFF10271E),
      'tileEmber': Color(0xFF321C13),
      'tileMist': Color(0xFF1B1B1B),
      'tileInk': Color(0xFFF4F4F4),
      'onTileInk': Brand.ink,
      'tileLeafBadge': Color(0xFF242424),
      'tileLeafIcon': Color(0xFFF4F4F4),
      'tileLeafEdge': Color(0x00000000),
      'tileEmberBadge': Color(0xFF242424),
      'tileEmberIcon': Color(0xFFF4F4F4),
      'tileEmberEdge': Color(0x00000000),
      'tileMistBadge': Color(0xFF242424),
      'tileMistIcon': Color(0xFFF4F4F4),
      'tileInkBadge': Color(0xFF242424),
      'tileInkIcon': Color(0xFFF4F4F4),
      'tileSheen': Color(0x00000000),
      'primaryGlow': Color(0x00000000),
      'nav': Color(0xFF1B1B1B),
      'onNav': Color(0xFF9E9E9E),
      'navSelected': Color(0xFFF4F4F4),
      'onNavSelected': Brand.ink,
    },
  );

  // A: near-black ink; tints stay dark but get coloured hairlines and
  // luminous icons on tinted badges, so colour reads as light, not fill.
  static final _darkInk = _darkScheme(
    background: const Color(0xFF090A09),
    foreground: const Color(0xFFF2F4F2),
    card: const Color(0xFF141614),
    raised: const Color(0xFF1D201D),
    mutedForeground: const Color(0xFF9AA39C),
    hairline: const Color(0xFF272B27),
    custom: const {
      'badge': Color(0xFF1D201D),
      'tileLeaf': Color(0xFF0B1F16),
      'tileEmber': Color(0xFF22120A),
      'tileMist': Color(0xFF141614),
      'tileInk': Color(0xFFEDF0EB),
      'onTileInk': Color(0xFF0E100E),
      'tileLeafBadge': Color(0xFF123A2A),
      'tileLeafIcon': Color(0xFF52E0A4),
      'tileLeafEdge': Color(0xFF1E5E42),
      'tileEmberBadge': Color(0xFF41200F),
      'tileEmberIcon': Color(0xFFFF9466),
      'tileEmberEdge': Color(0xFF703519),
      'tileMistBadge': Color(0xFF1D201D),
      'tileMistIcon': Color(0xFFF2F4F2),
      'tileInkBadge': Color(0xFF0E100E),
      'tileInkIcon': Color(0xFFEDF0EB),
      'tileSheen': Color(0x00000000),
      'primaryGlow': Color(0x00000000),
      'nav': Color(0xFF141614),
      'onNav': Color(0xFF9AA39C),
      'navSelected': Color(0xFFEDF0EB),
      'onNavSelected': Color(0xFF0E100E),
    },
  );

  // B: lifted graphite; saturated tile fills with a faint top sheen, the
  // light theme's white icon badges, and a leaf glow under the scan button.
  static final _darkGraphite = _darkScheme(
    background: const Color(0xFF1B1C1E),
    foreground: const Color(0xFFF5F5F4),
    card: const Color(0xFF26272A),
    raised: const Color(0xFF313236),
    mutedForeground: const Color(0xFFA9ABAF),
    hairline: const Color(0xFF37393D),
    custom: const {
      'badge': Color(0xFF313236),
      'tileLeaf': Color(0xFF17513A),
      'tileEmber': Color(0xFF5C2B17),
      'tileMist': Color(0xFF26272A),
      'tileInk': Color(0xFFF5F5F4),
      'onTileInk': Brand.ink,
      'tileLeafBadge': Color(0xFFF5F5F4),
      'tileLeafIcon': Brand.ink,
      'tileLeafEdge': Color(0x00000000),
      'tileEmberBadge': Color(0xFFF5F5F4),
      'tileEmberIcon': Brand.ink,
      'tileEmberEdge': Color(0x00000000),
      'tileMistBadge': Color(0xFFF5F5F4),
      'tileMistIcon': Brand.ink,
      'tileInkBadge': Color(0xFF1B1C1E),
      'tileInkIcon': Color(0xFFF5F5F4),
      'tileSheen': Color(0x14FFFFFF),
      'primaryGlow': Color(0x8C0A8A5A),
      'nav': Color(0xFF26272A),
      'onNav': Color(0xFFA9ABAF),
      'navSelected': Color(0xFFF5F5F4),
      'onNavSelected': Brand.ink,
    },
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
