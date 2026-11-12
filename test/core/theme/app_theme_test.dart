import 'dart:math';

import 'package:cleanleaf/core/theme/app_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  final themes = {'light': AppTheme.light, 'dark': AppTheme.dark};

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    final c = theme.colorScheme;
    test('$name defines every brand token', () {
      expect(
        () => [
          c.highlight,
          c.leafText,
          c.hairline,
          c.badge,
          c.tileLeaf,
          c.tileEmber, //
          c.tileMist, c.tileInk, c.onTileInk, c.tileLeafBadge,
          c.tileLeafIcon, c.tileLeafEdge, c.tileEmberBadge, c.tileEmberIcon,
          c.tileEmberEdge, c.tileMistBadge, c.tileMistIcon, c.tileInkBadge,
          c.tileInkIcon, c.nav, c.onNav,
          c.navSelected, c.onNavSelected,
        ],
        returnsNormally,
      );
    });

    test('$name text pairs meet AA', () {
      Color caption(Color on, Color tile) =>
          Color.alphaBlend(on.withValues(alpha: 0.72), tile);
      final pairs = {
        'caption on tileLeaf': (caption(c.foreground, c.tileLeaf), c.tileLeaf),
        'caption on tileEmber': (
          caption(c.foreground, c.tileEmber),
          c.tileEmber,
        ),
        'caption on tileMist': (caption(c.foreground, c.tileMist), c.tileMist),
        'caption on tileInk': (caption(c.onTileInk, c.tileInk), c.tileInk),
        'muted on background': (c.mutedForeground, c.background),
        'muted on card': (c.mutedForeground, c.card),
        'onNav on nav': (c.onNav, c.nav),
        'onNavSelected on navSelected': (c.onNavSelected, c.navSelected),
        'leafText on card': (c.leafText, c.card),
        'leafText on background': (c.leafText, c.background),
        'toast text on toast': (c.onTileInk, c.tileInk),
        'foreground on muted': (c.foreground, c.muted),
        'error toast text': (
          theme.destructiveToastTheme.titleStyle!.color!,
          theme.destructiveToastTheme.backgroundColor!,
        ),
      };
      for (final MapEntry(key: label, value: (fg, bg)) in pairs.entries) {
        expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: label);
      }
      // Leaf as text or outline (selected page, ring) needs the 3:1 UI bar.
      expect(_contrast(c.primary, c.card), greaterThanOrEqualTo(3));
    });
  }

  test('dark tile icons stay visible on their badges', () {
    final c = AppTheme.dark.colorScheme;
    for (final (icon, badge) in [
      (c.tileLeafIcon, c.tileLeafBadge),
      (c.tileEmberIcon, c.tileEmberBadge),
      (c.tileMistIcon, c.tileMistBadge),
      (c.tileInkIcon, c.tileInkBadge),
    ]) {
      expect(_contrast(icon, badge), greaterThanOrEqualTo(3));
    }
  });
}
