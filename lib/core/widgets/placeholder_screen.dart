import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/spacing.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = ShadTheme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textTheme.h2),
              if (subtitle != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(subtitle!, style: textTheme.muted),
              ],
              if (action != null) ...[
                const SizedBox(height: Spacing.xl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
