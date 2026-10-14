import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin_auth_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/auth_layout.dart';
import '../../widgets/captcha_field.dart';
import '../../widgets/forgot_password_dialog.dart';
import '../../widgets/google_sign_in_button.dart';
import '../legal/legal_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaKey = GlobalKey<CaptchaFieldState>();

  var _isSubmitting = false;
  var _obscurePassword = true;
  String? _captchaToken;

  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final captchaToken = _captchaToken;
    if (captchaToken == null) return;

    setState(() => _isSubmitting = true);
    try {
      await AdminAuthService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        captchaToken: captchaToken,
      );
      // AdminGate reacts to the auth-state stream.
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Something went wrong. Please try again.');
      debugPrint('LoginScreen: sign-in error $e');
    } finally {
      // Tokens are single-use.
      _captchaKey.currentState?.reset();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    await showForgotPasswordDialog(
      context,
      initialEmail: _emailController.text.trim(),
    );
  }

  void _goToRegister() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      builder: (context, isWide) {
        final theme = Theme.of(context);
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isWide) ...[
                const AuthLogo(),
                const SizedBox(height: AppSpacing.md),
              ],
              Text(
                'Admin sign in',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Log in to the IsdaSafe admin panel',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _emailController,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return 'Enter your email';
                  if (!_emailRegExp.hasMatch(trimmed)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _passwordController,
                enabled: !_isSubmitting,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Enter your password'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isSubmitting ? null : _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: CaptchaField(
                  key: _captchaKey,
                  onTokenChanged: (token) =>
                      setState(() => _captchaToken = token),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: (_isSubmitting || _captchaToken == null)
                    ? null
                    : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Log in'),
              ),
              GoogleSignInSection(enabled: !_isSubmitting),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Need admin access?', style: theme.textTheme.bodyMedium),
                  TextButton(
                    onPressed: _isSubmitting ? null : _goToRegister,
                    child: const Text('Register'),
                  ),
                ],
              ),
              const LegalLinks(),
            ],
          ),
        );
      },
    );
  }
}
