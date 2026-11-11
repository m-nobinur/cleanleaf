import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/placeholder_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      title: 'Library',
      subtitle: 'No documents yet.',
      action: ShadButton(
        leading: const Icon(LucideIcons.scanLine),
        onPressed: () => context.push(AppRoutes.capture),
        child: const Text('Scan'),
      ),
    );
  }
}
