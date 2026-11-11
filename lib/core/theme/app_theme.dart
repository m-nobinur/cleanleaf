import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../widgets/modal_close_button.dart';
import 'radii.dart';
import 'spacing.dart';

/// Brand palette: ink, mist, leaf (primary actions), ember (sparing highlights).
abstract final class Brand {
  static const ink = Color(0xFF111111);
  static const mist = Color(0xFFE7E7E7);
  static const leaf = Color(0xFF0A8A5A);
  static const ember = Color(0xFFEC5C1D);
}

extension BrandColors on ShadColorScheme {
  Color get highlight => custom['highlight']!;

  /// Leaf for small text and icons: brand leaf misses 4.5:1 on cards.
  Color get leafText => custom['leafText']!;
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
  Color get nav => custom['nav']!;
  Color get onNav => custom['onNav']!;
  Color get navSelected => custom['navSelected']!;
  Color get onNavSelected => custom['onNavSelected']!;
}

/// Named v2 text styles; colour comes from the surrounding DefaultTextStyle.
extension AppText on ShadTextTheme {
  TextStyle get greeting => _geist(36, -0.015, height: 1.08);
  TextStyle get sheetTitle => _geist(24, -0.015, height: 1.2);
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
        'leafText': Color(0xFF087A50),
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
        'nav': Brand.ink,
        'onNav': Brand.mist,
        'navSelected': Color(0xFFFFFFFF),
        'onNavSelected': Brand.ink,
      },
    ),
  );

  // Deep ink: tints stay dark but get coloured hairlines and luminous icons
  // on tinted badges, so colour reads as light, not fill (T-034, variant A).
  static final dark = _theme(
    Brightness.dark,
    const ShadColorScheme(
      background: Color(0xFF090A09),
      foreground: Color(0xFFF2F4F2),
      card: Color(0xFF141614),
      cardForeground: Color(0xFFF2F4F2),
      popover: Color(0xFF141614),
      popoverForeground: Color(0xFFF2F4F2),
      primary: Brand.leaf,
      primaryForeground: Color(0xFFFFFFFF),
      secondary: Color(0xFF1D201D),
      secondaryForeground: Color(0xFFF2F4F2),
      muted: Color(0xFF1D201D),
      mutedForeground: Color(0xFF9AA39C),
      accent: Color(0xFF1D201D),
      accentForeground: Color(0xFFF2F4F2),
      destructive: Color(0xFFF04438),
      destructiveForeground: Color(0xFFFFFFFF),
      border: Color(0xFF272B27),
      input: Color(0xFF272B27),
      ring: Brand.leaf,
      selection: Color(0x550A8A5A),
      custom: {
        'highlight': Brand.ember,
        'leafText': Color(0xFF4ED69B),
        'hairline': Color(0xFF272B27),
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
        'nav': Color(0xFF141614),
        'onNav': Color(0xFF9AA39C),
        'navSelected': Color(0xFFEDF0EB),
        'onNavSelected': Color(0xFF0E100E),
      },
    ),
  );

  static ShadThemeData _theme(Brightness brightness, ShadColorScheme colors) {
    final text = ShadTextTheme();
    const sheetRadius = BorderRadius.vertical(top: Radius.circular(Radii.lg));
    const modalRadius = BorderRadius.all(Radius.circular(Radii.lg));
    const toastRadius = BorderRadius.all(Radius.circular(Radii.md));
    final toastTitle = text.small.copyWith(fontWeight: FontWeight.w500);
    // Phones sit below shadcn's sm breakpoint, which centres titles and
    // squares off corners unless told otherwise.
    return ShadThemeData(
      brightness: brightness,
      colorScheme: colors,
      radius: _radius,
      // shadcn's muted style has no colour, so radio sublabels and other
      // DefaultTextStyle users rendered it invisible in light mode.
      textTheme: text.copyWith(
        muted: text.muted.copyWith(color: colors.mutedForeground),
      ),
      // 48 dp touch targets throughout (design.md, Android guideline).
      buttonSizesTheme: const ShadButtonSizesTheme(
        regular: ShadButtonSizeTheme(
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: 20),
        ),
        lg: ShadButtonSizeTheme(
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: 32),
        ),
        icon: ShadButtonSizeTheme(
          height: 48,
          width: 48,
          padding: EdgeInsets.zero,
        ),
      ),
      inputTheme: const ShadInputTheme(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      sheetTheme: const ShadSheetTheme(
        radius: sheetRadius,
        closeIcon: ModalCloseButton(),
        closeIconPosition: modalClosePosition,
        removeBorderRadiusWhenTiny: false,
        titleTextAlign: TextAlign.start,
        descriptionTextAlign: TextAlign.start,
      ),
      primaryDialogTheme: ShadDialogTheme(
        radius: modalRadius,
        removeBorderRadiusWhenTiny: false,
        backgroundColor: colors.card,
        border: Border.all(color: colors.custom['hairline']!),
        titleStyle: text.sheetTitle.copyWith(color: colors.foreground),
        descriptionStyle: text.muted.copyWith(color: colors.mutedForeground),
        titleTextAlign: TextAlign.start,
        descriptionTextAlign: TextAlign.start,
        gap: Spacing.sm,
        actionsGap: Spacing.sm,
        // Leaves a margin on phones, where shadcn would go edge to edge.
        constraints: const BoxConstraints(maxWidth: 328),
      ),
      // White on leaf passes AA only as large text (bold 14+ or 18+).
      primaryButtonTheme: ShadButtonTheme(
        textStyle: text.small.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      // shadcn tints outline and ghost text with primary; ours stay ink.
      outlineButtonTheme: ShadButtonTheme(
        foregroundColor: colors.foreground,
        pressedForegroundColor: colors.foreground,
      ),
      ghostButtonTheme: ShadButtonTheme(
        foregroundColor: colors.foreground,
        pressedForegroundColor: colors.foreground,
      ),
      // Toasts invert the surface so they read over any screen. They time out
      // on their own, so they drop shadcn's 20 dp close icon.
      primaryToastTheme: ShadToastTheme(
        closeIcon: const SizedBox.shrink(),
        backgroundColor: colors.custom['tileInk'],
        titleStyle: toastTitle.copyWith(color: colors.custom['onTileInk']),
        descriptionStyle: text.muted.copyWith(
          color: colors.custom['onTileInk'],
        ),
        radius: toastRadius,
        border: ShadBorder.none,
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      ),
      destructiveToastTheme: ShadToastTheme(
        closeIcon: const SizedBox.shrink(),
        // Deeper than [destructive] so white 14 sp text passes AA in dark too.
        backgroundColor: const Color(0xFFB42318),
        titleStyle: toastTitle.copyWith(color: colors.destructiveForeground),
        radius: toastRadius,
        border: ShadBorder.none,
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      ),
    );
  }
}
