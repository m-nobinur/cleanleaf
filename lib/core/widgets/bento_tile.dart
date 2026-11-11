import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';

enum TileTone {
  leaf,
  ember,
  mist,
  ink;

  ({Color background, Color foreground, Color badge, Color icon, Color edge})
  colors(ShadColorScheme c) => switch (this) {
    leaf => (
      background: c.tileLeaf,
      foreground: c.foreground,
      badge: c.tileLeafBadge,
      icon: c.tileLeafIcon,
      edge: c.tileLeafEdge,
    ),
    ember => (
      background: c.tileEmber,
      foreground: c.foreground,
      badge: c.tileEmberBadge,
      icon: c.tileEmberIcon,
      edge: c.tileEmberEdge,
    ),
    mist => (
      background: c.tileMist,
      foreground: c.foreground,
      badge: c.tileMistBadge,
      icon: c.tileMistIcon,
      edge: c.hairline,
    ),
    ink => (
      background: c.tileInk,
      foreground: c.onTileInk,
      badge: c.tileInkBadge,
      icon: c.tileInkIcon,
      edge: const Color(0x00000000),
    ),
  };
}

/// A tinted, pressable tile for the home bento and the scan-mode sheet.
class BentoTile extends StatefulWidget {
  const BentoTile({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    required this.caption,
    this.onTap,
    this.badge,
  });

  final TileTone tone;
  final IconData icon;
  final String title;
  final String caption;

  /// Null disables the tile.
  final VoidCallback? onTap;

  /// Small mono tag in the top-right corner, e.g. "SOON". A disabled tile
  /// with a badge is an unbuilt feature and is dimmed; without one it keeps
  /// full colour and its caption says why it is idle.
  final String? badge;

  @override
  State<BentoTile> createState() => _BentoTileState();
}

class _BentoTileState extends State<BentoTile> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final (:background, :foreground, :badge, :icon, :edge) = widget.tone.colors(
      colors,
    );
    final enabled = widget.onTap != null;

    final content = Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
                child: Icon(widget.icon, size: 24, color: icon),
              ),
              const Spacer(),
              if (widget.badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.badge,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    widget.badge!,
                    style: text.monoLabel.copyWith(color: colors.foreground),
                  ),
                ),
            ],
          ),
          // Scales the text down a touch on narrow phones or large font
          // sizes instead of overflowing the tile.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Align(
                alignment: Alignment.bottomLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: SizedBox(
                    width: box.maxWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.tileTitle.copyWith(color: foreground),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.caption.copyWith(
                            color: foreground.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: '${widget.title}. ${widget.caption}',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Opacity(
            opacity: enabled || widget.badge == null ? 1 : 0.55,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(Radii.lg),
                border: edge.a == 0 ? null : Border.all(color: edge),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
