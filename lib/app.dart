import 'package:flutter/material.dart';

import 'screens/auth/admin_gate.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// Suppresses the draggable scrollbar Flutter draws by default on
/// mouse-based platforms (web, desktop) for every scrollable widget.
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class IsdaSafeAdminApp extends StatelessWidget {
  const IsdaSafeAdminApp({super.key, this.home = const AdminGate()});

  /// The first screen. Defaults to the admin gate; tests swap it out so they
  /// don't need a Supabase session.
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => _buildApp(ThemeController.instance.themeMode),
    );
  }

  Widget _buildApp(ThemeMode themeMode) {
    return MaterialApp(
      title: 'IsdaSafe Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      scrollBehavior: const _NoScrollbarBehavior(),
      // On wide screens a floating snackbar would span the whole window; keep
      // it a readable card instead.
      builder: (context, child) {
        final theme = Theme.of(context);
        final wide = MediaQuery.sizeOf(context).width > 560;
        return Theme(
          data: theme.copyWith(
            snackBarTheme: theme.snackBarTheme.copyWith(
              width: wide ? 480 : null,
            ),
          ),
          child: child!,
        );
      },
      home: home,
    );
  }
}
