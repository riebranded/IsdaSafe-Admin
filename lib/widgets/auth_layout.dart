import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// The farmer app's login layout: on wide screens a navy branding panel
/// beside a raised form card (always light, whatever the theme); on narrow
/// screens just the form.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.builder, this.showBack = false});

  /// Builds the form; `isWide` says whether the branding panel is showing
  /// (the form then leaves out its own logo).
  final Widget Function(BuildContext context, bool isWide) builder;

  /// Shows a back button (for screens pushed on top of Login).
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

    if (!isWide) {
      return Scaffold(
        appBar: showBack ? AppBar() : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: builder(context, false),
              ),
            ),
          ),
        ),
      );
    }

    return Theme(
      data: AppTheme.light,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            backgroundColor: theme.colorScheme.surfaceContainerLow,
            body: SafeArea(
              child: Row(
                children: [
                  const Expanded(child: _BrandingPanel()),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Container(
                          margin: const EdgeInsets.all(AppSpacing.xxl),
                          constraints: const BoxConstraints(maxWidth: 480),
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 40,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showBack)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: BackButton(
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                  ),
                                ),
                              builder(context, true),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Small logo shown above the form when there's no branding panel.
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Image.asset(
          'assets/branding/logo.png',
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          semanticLabel: 'IsdaSafe logo',
        ),
      ),
    );
  }
}

class _BrandingPanel extends StatelessWidget {
  const _BrandingPanel();

  static const _navy = Color(0xFF0B2644);
  static const _navyDeep = Color(0xFF081D37);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _navyDeep],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Image.asset(
                    'assets/branding/logo.png',
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                    semanticLabel: 'IsdaSafe logo',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'IsdaSafe Admin',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Monitor every pond and device, in one place.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
