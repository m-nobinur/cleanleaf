import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

/// A 48 dp circular icon button on a card surface with a hairline border.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: ShadIconButton(
        width: 48,
        height: 48,
        backgroundColor: colors.card,
        hoverBackgroundColor: colors.muted,
        pressedBackgroundColor: colors.muted,
        foregroundColor: colors.foreground,
        hoverForegroundColor: colors.foreground,
        decoration: ShadDecoration(
          shape: BoxShape.circle,
          border: ShadBorder.all(color: colors.hairline),
        ),
        icon: Icon(icon, size: 22),
        onPressed: onPressed,
      ),
    );
  }
}
