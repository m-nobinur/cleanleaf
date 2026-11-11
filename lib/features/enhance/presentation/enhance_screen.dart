import 'package:flutter/widgets.dart';

import '../../../core/widgets/placeholder_screen.dart';

class EnhanceScreen extends StatelessWidget {
  const EnhanceScreen({super.key, required this.pageId});

  final String pageId;

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(title: 'Enhance', subtitle: 'Page $pageId');
  }
}
