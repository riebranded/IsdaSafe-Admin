import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_auth_service.dart';
import '../theme/app_spacing.dart';

/// "or" divider + "Continue with Google", as on the farmer app's login.
/// Renders nothing where Google sign-in isn't supported (desktop/iOS).
class GoogleSignInSection extends StatefulWidget {
  const GoogleSignInSection({super.key, this.enabled = true});

  final bool enabled;

  @override
  State<GoogleSignInSection> createState() => _GoogleSignInSectionState();
}

class _GoogleSignInSectionState extends State<GoogleSignInSection> {
  var _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final signedIn = await AdminAuthService.signInWithGoogle();
      // Native sign-in completes here; drop any pushed auth screen (e.g.
      // Register) so AdminGate underneath shows the result.
      if (signedIn && AdminAuthService.currentSession != null) {
        navigator.popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      debugPrint('GoogleSignInSection: error $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Google sign-in failed. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AdminAuthService.isGoogleSignInSupported) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('or', style: theme.textTheme.bodySmall),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: (_busy || !widget.enabled) ? null : _signIn,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.g_mobiledata, size: 28),
          label: const Text('Continue with Google'),
        ),
      ],
    );
  }
}
