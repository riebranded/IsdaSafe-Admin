import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin_auth_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/auth_layout.dart';
import '../../widgets/password_strength_checklist.dart';

/// Where a recovery session (reset code or email link) chooses the new
/// password. AdminGate shows it while [AdminAuthService.recoveryPending].
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  var _obscure = true;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!isStrongPassword(_password.text)) {
      setState(() => _error = 'Password does not meet all the requirements');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminAuthService.updatePassword(_password.text);
      AdminAuthService.recoveryPending.value = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your password was updated.')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_reset),
        title: const Text('Cancel password reset?'),
        content: const Text(
          'You\'ll be signed out and your password won\'t be changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep resetting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await AdminAuthService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      builder: (context, isWide) {
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_reset, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Set a new password',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofocus: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'New password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            PasswordStrengthChecklist(password: _password.text),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save new password'),
            ),
            TextButton(
              onPressed: _busy ? null : _cancel,
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}
