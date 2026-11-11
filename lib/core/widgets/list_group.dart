import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import 'bento_tile.dart';

const _badgeSize = 40.0;
const _rowPadding = Spacing.lg;

/// A card of [ListRow]s separated by inset hairlines, for sheets and menus.
class ListGroup extends StatelessWidget {
  ListGroup({super.key, required List<Widget> children})
    : itemCount = children.length,
      itemBuilder = ((_, i) => children[i]),
      _lazy = false;

  /// Builds rows on demand and scrolls within its parent's height limit.
  const ListGroup.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  }) : _lazy = true;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool _lazy;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final radius = BorderRadius.circular(Radii.md);
    final divider = Padding(
      padding: const EdgeInsets.only(
        left: _rowPadding + _badgeSize + Spacing.md,
      ),
      child: SizedBox(height: 1, child: ColoredBox(color: colors.hairline)),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: radius,
        border: Border.all(color: colors.hairline),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: _lazy
            ? ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: itemCount,
                separatorBuilder: (_, _) => divider,
                itemBuilder: itemBuilder,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < itemCount; i++) ...[
                    if (i > 0) divider,
                    itemBuilder(context, i),
                  ],
                ],
              ),
      ),
    );
  }
}

/// One row: a tinted icon badge (or [leading]), a title, an optional caption
/// and a chevron when tappable.
class ListRow extends StatefulWidget {
  const ListRow({
    super.key,
    required this.title,
    this.icon,
    this.tone = TileTone.mist,
    this.leading,
    this.caption,
    this.captionIsMeta = false,
    this.trailing,
    this.onTap,
    this.destructive = false,
  }) : assert(icon != null || leading != null);

  final String title;
  final IconData? icon;
  final TileTone tone;

  /// Replaces the icon badge, e.g. with a thumbnail.
  final Widget? leading;
  final String? caption;

  /// Sets the caption in mono, for counts, sizes and dates.
  final bool captionIsMeta;

  /// Defaults to a chevron when [onTap] is set.
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  State<ListRow> createState() => _ListRowState();
}

class _ListRowState extends State<ListRow> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final tone = widget.tone.colors(colors);
    final onTap = widget.onTap;
    final titleColor = widget.destructive
        ? colors.destructive
        : colors.foreground;

    final leading =
        widget.leading ??
        Container(
          width: _badgeSize,
          height: _badgeSize,
          decoration: BoxDecoration(
            color: widget.destructive
                ? colors.destructive.withValues(alpha: 0.1)
                : tone.background,
            shape: BoxShape.circle,
            // Always bordered so every badge's icon sits on the same line.
            border: Border.all(
              color: widget.destructive ? const Color(0x00000000) : tone.edge,
            ),
          ),
          child: Icon(
            widget.icon,
            size: 20,
            color: widget.destructive
                ? colors.destructive
                : widget.tone == TileTone.ink
                ? tone.foreground
                : tone.icon,
          ),
        );

    final trailing =
        widget.trailing ??
        (onTap == null
            ? null
            : Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: colors.mutedForeground,
              ));

    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(minHeight: 64),
      color: _pressed ? colors.muted : colors.card,
      padding: const EdgeInsets.symmetric(
        horizontal: _rowPadding,
        vertical: Spacing.md,
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.p.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: titleColor,
                  ),
                ),
                if (widget.caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.caption!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (widget.captionIsMeta
                                ? theme.textTheme.monoMeta
                                : theme.textTheme.caption)
                            .copyWith(color: colors.mutedForeground),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Spacing.sm),
            trailing,
          ],
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: [widget.title, ?widget.caption].join('. '),
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onTapDown: onTap == null ? null : (_) => _setPressed(true),
        onTapUp: onTap == null ? null : (_) => _setPressed(false),
        onTapCancel: onTap == null ? null : () => _setPressed(false),
        child: row,
      ),
    );
  }
}
