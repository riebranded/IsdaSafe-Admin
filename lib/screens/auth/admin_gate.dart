import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin_auth_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/auth_layout.dart';
import '../../widgets/birth_date_field.dart';
import '../../widgets/name_fields.dart';
import '../../widgets/new_password_fields.dart';
import '../../widgets/phone_input.dart';
import '../dashboard_screen.dart';
import '../legal/legal_screen.dart';
import 'login_screen.dart';
import 'phone_verification_screen.dart';
import 'reset_password_screen.dart';

/// Shows Login when signed out, the set-new-password screen during a
/// password reset, a profile step for an admin missing a first/last name or
/// date of birth,
/// the OTP step until the admin's mobile number is verified,
/// the dashboard for an approved admin, and otherwise a waiting/declined
/// screen — or, for a signed-in account with no admin row (a first-time
/// Google sign-in, or a farmer account), a request form.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  String? _checkedUserId;
  Future<AdminProfile?>? _profileFuture;

  void _recheck() => setState(() => _profileFuture = null);

  @override
  void initState() {
    super.initState();
    AdminAuthService.recoveryPending.addListener(_onRecoveryChanged);
    AdminAuthService.adminRequestFiled.addListener(_onRequestFiled);
  }

  @override
  void dispose() {
    AdminAuthService.recoveryPending.removeListener(_onRecoveryChanged);
    AdminAuthService.adminRequestFiled.removeListener(_onRequestFiled);
    super.dispose();
  }

  void _onRequestFiled() {
    if (mounted) _recheck();
  }

  void _onRecoveryChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AdminAuthService.onAuthStateChange,
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ?? AdminAuthService.currentSession;
        if (session == null) {
          _checkedUserId = null;
          _profileFuture = null;
          return const LoginScreen();
        }
        // Signed in by a reset code or link: choose the new password first.
        if (AdminAuthService.recoveryPending.value) {
          return const ResetPasswordScreen();
        }
        if (_checkedUserId != session.user.id) {
          _checkedUserId = session.user.id;
          _profileFuture = null;
        }

        return FutureBuilder<AdminProfile?>(
          future: _profileFuture ??= AdminAuthService.fetchOwnProfile(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (profileSnapshot.hasError) {
              return _NoAccessScreen(
                icon: Icons.cloud_off,
                title: 'Couldn\'t check your access',
                message: 'Check your connection and try again.',
                onRetry: _recheck,
              );
            }
            final profile = profileSnapshot.data;
            if (profile == null) {
              return _RequestAccessScreen(onRequested: _recheck);
            }
            // Admins from before first/last names and dates of birth were
            // asked give whatever's missing now.
            if (profile.status != AdminStatus.rejected &&
                (!profile.hasFirstAndLastName || profile.birthDate == null)) {
              return _ProfileSetupScreen(profile: profile, onSaved: _recheck);
            }
            // Every admin (the very first, auto-approved one included)
            // verifies the number their OTP codes go to before anything else.
            if (profile.status != AdminStatus.rejected &&
                !profile.phoneVerified) {
              return PhoneVerificationScreen(
                initialPhone: profile.phone,
                onVerified: _recheck,
              );
            }
            return switch (profile.status) {
              AdminStatus.approved => const DashboardScreen(),
              AdminStatus.pending => _NoAccessScreen(
                icon: Icons.hourglass_top,
                title: 'Waiting for approval',
                message:
                    'Your admin account has been created. An existing admin '
                    'needs to approve it before you can use the panel.',
                onRetry: _recheck,
              ),
              AdminStatus.rejected => const _NoAccessScreen(
                icon: Icons.block,
                title: 'Access denied',
                message: 'Your request for admin access was declined.',
              ),
              AdminStatus.notAdmin => _RequestAccessScreen(
                onRequested: _recheck,
              ),
            };
          },
        );
      },
    );
  }
}

class _NoAccessScreen extends StatelessWidget {
  const _NoAccessScreen({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      builder: (context, isWide) {
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (AdminAuthService.currentUser?.email case final email?) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Signed in as $email',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (onRetry != null) ...[
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            OutlinedButton(
              onPressed: AdminAuthService.signOut,
              child: const Text('Sign out'),
            ),
          ],
        );
      },
    );
  }
}

/// For a signed-in account with no admin row: confirm a first and last
/// name, give the
/// mobile number for OTP codes and file an admin request (needs an existing
/// admin's approval). A Google account with no password yet (a brand-new
/// one) also sets one here, so the admin can log in with email too; an
/// existing farmer account keeps its password.
class _RequestAccessScreen extends StatefulWidget {
  const _RequestAccessScreen({required this.onRequested});

  final VoidCallback onRequested;

  @override
  State<_RequestAccessScreen> createState() => _RequestAccessScreenState();
}

class _RequestAccessScreenState extends State<_RequestAccessScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _googleName = splitFullName(AdminAuthService.currentUserName);
  late final _firstName = TextEditingController(text: _googleName.first);
  late final _lastName = TextEditingController(text: _googleName.last);
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _needsPassword = !AdminAuthService.hasPasswordLogin;
  DateTime? _birthDate;
  var _busy = false;
  var _agreedToTerms = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || !_agreedToTerms) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (_needsPassword) {
        await AdminAuthService.updatePassword(_password.text);
      }
      await AdminAuthService.requestAdminAccess(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: toE164Phone(_phone.text),
        birthDate: _birthDate!,
      );
      widget.onRequested();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      debugPrint('RequestAccessScreen: error $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t send your request. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              Icon(
                Icons.admin_panel_settings_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Request admin access',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This account isn\'t an admin yet. Send a request and an '
                'existing admin will review it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (AdminAuthService.currentUser?.email case final email?) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Signed in as $email',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              NameFields(
                firstName: _firstName,
                lastName: _lastName,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.md),
              BirthDateField(
                enabled: !_busy,
                onChanged: (date) => setState(() => _birthDate = date),
              ),
              const SizedBox(height: AppSpacing.md),
              PhoneNumberField(
                controller: _phone,
                enabled: !_busy,
                textInputAction: _needsPassword
                    ? TextInputAction.next
                    : TextInputAction.done,
                onFieldSubmitted: _needsPassword ? null : (_) => _submit(),
              ),
              if (_needsPassword) ...[
                const SizedBox(height: AppSpacing.md),
                NewPasswordFields(
                  controller: _password,
                  enabled: !_busy,
                  helperText: 'Lets you also log in with your email',
                  onSubmitted: _submit,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              LegalConsentCheckbox(
                value: _agreedToTerms,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _agreedToTerms = value),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: (_busy || !_agreedToTerms) ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Request access'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: _busy ? null : AdminAuthService.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// For an admin missing a first/last name or date of birth (one from before
/// they were asked at sign-up): asks for just what's missing. Under 18 can't
/// continue.
class _ProfileSetupScreen extends StatefulWidget {
  const _ProfileSetupScreen({required this.profile, required this.onSaved});

  final AdminProfile profile;
  final VoidCallback onSaved;

  @override
  State<_ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<_ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _needsName = !widget.profile.hasFirstAndLastName;
  late final _needsBirthDate = widget.profile.birthDate == null;
  late final _guess = _initialGuess();
  late final _firstName = TextEditingController(text: _guess.first);
  late final _lastName = TextEditingController(text: _guess.last);
  DateTime? _birthDate;
  var _busy = false;

  /// What's on file, else a split of the full name — unless that's just the
  /// email address the account was filed under.
  ({String first, String last}) _initialGuess() {
    final p = widget.profile;
    if (p.firstName != null || p.lastName != null) {
      return (first: p.firstName ?? '', last: p.lastName ?? '');
    }
    return p.fullName.contains('@')
        ? (first: '', last: '')
        : splitFullName(p.fullName);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      if (_needsName) {
        await AdminAuthService.updateOwnName(
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
        );
      }
      if (_needsBirthDate) {
        await AdminAuthService.setOwnBirthDate(_birthDate!);
      }
      widget.onSaved();
    } on PostgrestException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      debugPrint('ProfileSetupScreen: error $e');
      if (mounted) _showError('Couldn\'t save your details. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final asking = [
      if (_needsName) 'your first and last name',
      if (_needsBirthDate) 'your date of birth',
    ].join(' and ');
    return AuthLayout(
      builder: (context, isWide) {
        final theme = Theme.of(context);
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.badge_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Complete your profile',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Add $asking to keep using the admin panel. '
                '${_needsBirthDate ? 'Admins must be at least 18 years old.' : 'Other admins see your name on the Admins page.'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (AdminAuthService.currentUser?.email case final email?) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Signed in as $email',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (_needsName) ...[
                NameFields(
                  firstName: _firstName,
                  lastName: _lastName,
                  enabled: !_busy,
                  autofocus: true,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_needsBirthDate) ...[
                BirthDateField(
                  enabled: !_busy,
                  onChanged: (date) => setState(() => _birthDate = date),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: _busy ? null : AdminAuthService.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        );
      },
    );
  }
}
