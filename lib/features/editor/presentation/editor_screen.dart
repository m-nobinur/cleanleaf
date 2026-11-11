import 'package:flutter/widgets.dart';

import '../../../core/widgets/placeholder_screen.dart';

class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key, required this.pageId});

  final String pageId;

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(title: 'Edit corners', subtitle: 'Page $pageId');
  }
}
