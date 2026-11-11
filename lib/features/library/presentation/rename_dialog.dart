import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/widgets/modal_close_button.dart';

/// Resolves to the trimmed new title, or null when cancelled or unchanged.
Future<String?> showRenameDialog(BuildContext context, String current) async {
  final title = await showShadDialog<String>(
    context: context,
    barrierLabel: 'Dismiss',
    builder: (_) => _RenameDialog(current: current),
  );
  return title == current ? null : title;
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final title = _controller.text.trim();
    if (title.isNotEmpty) Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const ModalTitle('Rename document'),
      closeIcon: const ModalCloseButton(),
      closeIconPosition: modalClosePosition,
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(onPressed: _save, child: const Text('Save')),
      ],
      child: ShadInput(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _save(),
      ),
    );
  }
}
