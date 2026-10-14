import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin_auth_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/auth_layout.dart';
import '../../widgets/birth_date_field.dart';
import '../../widgets/captcha_field.dart';
import '../../widgets/google_sign_in_button.dart';
import '../../widgets/name_fields.dart';
import '../../widgets/password_strength_checklist.dart';
import '../../widgets/phone_input.dart';
import '../legal/legal_screen.dart';

/// Admin sign-up: first and last name, date of birth (18 or older), email, mobile number and password. AdminGate then
/// has the number verified by OTP, and the account stays a pending request
/// until an approved admin approves it.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _captchaKey = GlobalKey<CaptchaFieldState>();

  var _password = '';
  var _isSubmitting = false;
  var _obscurePassword = true;
  var _obscureConfirmPassword = true;
  var _agreedToTerms = false;
  DateTime? _birthDate;

  /// Why Register can't create this email (it already has an IsdaSafe
  /// login): explains how to make that account an admin instead.
  _AccountNotice? _notice;
  String? _captchaToken;

  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() {
      setState(() {
        _password = _passwordController.text;
        _notice = null;
      });
    });
    _emailController.addListener(() {
      if (_notice != null) {
        setState(() => _notice = null);
      }
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The email already has an IsdaSafe login (e.g. a farmer account): sign
  /// in to it and file the admin request with the name and number typed.
  /// AdminGate (underneath) then asks to verify the number.
  Future<void> _requestWithExistingAccount(
    String email,
    String captchaToken,
  ) async {
    try {
      await AdminAuthService.signIn(
        email: email,
        password: _passwordController.text,
        captchaToken: captchaToken,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      if (_looksLikeWrongPassword(e.message)) {
        setState(() => _notice = _AccountNotice.wrongPassword);
        return;
      }
      rethrow;
    }
    await AdminAuthService.requestAdminAccess(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      phone: toE164Phone(_phoneController.text),
      birthDate: _birthDate!,
    );
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Supabase's wording varies by version ("User already registered", "A
  /// user with this email address has already been registered", ...).
  static bool _looksLikeDuplicateEmail(String message) {
    final lower = message.toLowerCase();
    return lower.contains('already registered') ||
        lower.contains('already exists') ||
        lower.contains('already been registered');
  }

  static bool _looksLikeWrongPassword(String message) =>
      message.toLowerCase().contains('invalid login credentials');

  /// For a Google-only email: signs in with Google; AdminGate (underneath)
  /// then asks for the name, number and a password, like any new Google
  /// admin.
  Future<void> _continueWithGoogle() async {
    setState(() => _isSubmitting = true);
    try {
      final signedIn = await AdminAuthService.signInWithGoogle();
      if (signedIn && mounted && AdminAuthService.currentSession != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      debugPrint('RegisterScreen: Google sign-in error $e');
      if (mounted) _showError('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final captchaToken = _captchaToken;
    if (captchaToken == null || !_agreedToTerms) return;

    final email = _emailController.text.trim();
    setState(() {
      _isSubmitting = true;
      _notice = null;
    });
    try {
      // Admins and farmers share logins: an email already used in the
      // IsdaSafe app can't sign up again, but that account can become an
      // admin. Sign in to it with the password typed and file the request.
      switch (await AdminAuthService.emailSignInMethod(email)) {
        case EmailSignIn.password:
          await _requestWithExistingAccount(email, captchaToken);
          return;
        case EmailSignIn.googleOnly:
          // No password to sign in with: only Google gets into it.
          setState(() => _notice = _AccountNotice.googleOnly);
          return;
        case EmailSignIn.none:
          break;
      }
      final response = await AdminAuthService.register(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        birthDate: _birthDate!,
        email: email,
        password: _passwordController.text,
        phone: toE164Phone(_phoneController.text),
        captchaToken: captchaToken,
      );
      if (!mounted) return;
      if (response.session != null) {
        // Signed in: AdminGate (underneath) now shows the dashboard or the
        // waiting-for-approval screen.
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        // Email confirmation is on for the project.
        _showError('Check your email to confirm your account, then log in.');
        Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      if (_looksLikeDuplicateEmail(e.message)) {
        setState(() => _notice = _AccountNotice.wrongPassword);
      } else {
        _showError(e.message);
      }
    } catch (e) {
      if (mounted) _showError('Something went wrong. Please try again.');
      debugPrint('RegisterScreen: sign-up error $e');
    } finally {
      _captchaKey.currentState?.reset();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      showBack: true,
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
                'Request admin access',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'An existing admin approves new accounts before they can sign in.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              NameFields(
                firstName: _firstNameController,
                lastName: _lastNameController,
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: AppSpacing.md),
              BirthDateField(
                enabled: !_isSubmitting,
                onChanged: (date) => setState(() => _birthDate = date),
              ),
              const SizedBox(height: AppSpacing.md),
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
              PhoneNumberField(
                controller: _phoneController,
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _passwordController,
                enabled: !_isSubmitting,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
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
                validator: (value) => isStrongPassword(value ?? '')
                    ? null
                    : 'Password doesn\'t meet all the requirements',
              ),
              const SizedBox(height: AppSpacing.sm),
              PasswordStrengthChecklist(password: _password),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _confirmPasswordController,
                enabled: !_isSubmitting,
                obscureText: _obscureConfirmPassword,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                  ),
                ),
                validator: (value) => value != _passwordController.text
                    ? 'Passwords don\'t match'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_notice case final notice?) ...[
                const SizedBox(height: AppSpacing.md),
                _ExistingAccountNotice(
                  notice: notice,
                  onContinueWithGoogle: _isSubmitting
                      ? null
                      : _continueWithGoogle,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              LegalConsentCheckbox(
                value: _agreedToTerms,
                onChanged: _isSubmitting
                    ? null
                    : (value) => setState(() => _agreedToTerms = value),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: CaptchaField(
                  key: _captchaKey,
                  onTokenChanged: (token) =>
                      setState(() => _captchaToken = token),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed:
                    (_isSubmitting || _captchaToken == null || !_agreedToTerms)
                    ? null
                    : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Register'),
              ),
              GoogleSignInSection(enabled: !_isSubmitting),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Already an admin?', style: theme.textTheme.bodyMedium),
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    child: const Text('Log in'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _AccountNotice {
  /// A password login, but not this password.
  wrongPassword,

  /// A Google-only login: it has no password at all.
  googleOnly,
}

/// Shown when the email already has an IsdaSafe login (e.g. from the farmer
/// app), so Register can't create it: how to make that account an admin.
class _ExistingAccountNotice extends StatelessWidget {
  const _ExistingAccountNotice({
    required this.notice,
    required this.onContinueWithGoogle,
  });

  final _AccountNotice notice;
  final VoidCallback? onContinueWithGoogle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final googleOnly = notice == _AccountNotice.googleOnly;
    final canUseGoogle = AdminAuthService.isGoogleSignInSupported;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  googleOnly
                      ? 'This email already has an IsdaSafe account that signs '
                            'in with Google, so it has no password yet. '
                            'Continue with Google to make it an admin — you\'ll '
                            'add your name, number and a password there.'
                      : 'This email already has an IsdaSafe account (for '
                            'example from the farmer app), and that isn\'t its '
                            'password. Enter that account\'s current password '
                            'to make it an admin.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          if (googleOnly && canUseGoogle) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onContinueWithGoogle,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Continue with Google'),
            ),
          ],
        ],
      ),
    );
  }
}
