import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Where sheets and dialogs place [ModalCloseButton].
const modalClosePosition = ShadPosition(top: 14, right: 14);

/// The close control of every sheet and dialog: a muted 36 dp circle in a 48 dp target.
class ModalCloseButton extends StatelessWidget {
  const ModalCloseButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    void close() => Navigator.of(context).pop();
    return Semantics(
      label: 'Close',
      button: true,
      excludeSemantics: true,
      onTap: close,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: close,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.muted,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.x,
                size: 18,
                color: colors.mutedForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line sheet or dialog title that stays clear of [ModalCloseButton].
class ModalTitle extends StatelessWidget {
  const ModalTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 40),
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}
