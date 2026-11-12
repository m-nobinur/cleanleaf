import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class CleanleafApp extends ConsumerWidget {
  const CleanleafApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShadApp.router(
      title: 'Cleanleaf',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      // Only Material screen left is the licence page; keep it flat and on-brand.
      materialThemeBuilder: (context, theme) {
        final colors = ShadTheme.of(context).colorScheme;
        return theme.copyWith(
          cardColor: colors.card,
          appBarTheme: AppBarTheme(
            backgroundColor: colors.background,
            foregroundColor: colors.foreground,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
          ),
        );
      },
      // No AppBar sets the status bar style, so match it to the theme here.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: ShadTheme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: child!,
      ),
    );
  }
}
