import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_auth_service.dart';
import '../theme/app_spacing.dart';
import 'password_strength_checklist.dart';
import 'phone_input.dart';

// Settings → Credentials, modelled on the farmer app's `account_dialogs.dart`:
// change the phone number (code texted to the new number), the email (a
// confirmation link) and the password (code texted to the current number
// first). Each dialog resolves to a short success message for the caller to
// show, or null when cancelled.

final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String _errorText(Object e) => switch (e) {
  AuthException(:final message) => message,
  PostgrestException(:final message) => message,
  _ => 'Something went wrong. Please try again.',
};

Future<String?> showChangePhoneDialog(
  BuildContext context, {
  String? currentPhone,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ChangePhoneDialog(currentPhone: currentPhone),
);

Future<String?> showChangeEmailDialog(
  BuildContext context, {
  String? currentEmail,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ChangeEmailDialog(currentEmail: currentEmail),
);

Future<String?> showChangePasswordDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      // Closing goes through the "cancel?" confirmation (see the dialog).
      barrierDismissible: false,
      builder: (_) => const _ChangePasswordDialog(),
    );

/// The 6-digit code field shared by the phone and password dialogs.
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.error,
    required this.onChanged,
    required this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String? error;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: true,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: InputDecoration(
        labelText: 'Verification code',
        errorText: error,
      ),
      onChanged: (_) => onChanged(),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class _ChangePhoneDialog extends StatefulWidget {
  const _ChangePhoneDialog({this.currentPhone});

  final String? currentPhone;

  @override
  State<_ChangePhoneDialog> createState() => _ChangePhoneDialogState();
}

class _ChangePhoneDialogState extends State<_ChangePhoneDialog> {
  final _phone = TextEditingController();
  final _code = TextEditingController();

  /// The number the code went to; null while asking for it.
  String? _e164;
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final digits = _phone.text.trim();
    if (digits.length != 10 || !digits.startsWith('9')) {
      setState(
        () => _error = 'Enter a valid mobile number (e.g. 917 123 4567)',
      );
      return;
    }
    final e164 = toE164Phone(digits);
    if (e164 == widget.currentPhone) {
      setState(() => _error = 'That is already your number');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminAuthService.sendPhoneChangeOtp(e164);
      if (mounted) setState(() => _e164 = e164);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminAuthService.confirmPhoneChange(code);
      if (mounted) Navigator.of(context).pop('Phone number updated.');
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final awaitingCode = _e164 != null;
    return AlertDialog(
      title: const Text('Change phone number'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (awaitingCode) ...[
              Text(
                'Enter the code we texted to $_e164.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              _CodeField(
                controller: _code,
                enabled: !_busy,
                error: _error,
                onChanged: () {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: _verify,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _e164 = null;
                          _code.clear();
                          _error = null;
                        }),
                  child: const Text('Use a different number'),
                ),
              ),
            ] else ...[
              Text(
                'We\'ll text a code to the new number to verify it. Your '
                'current number stays until then. It can be the same number '
                'you use in the IsdaSafe app.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _phone,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.phone,
                inputFormatters: phoneInputFormatters,
                decoration: InputDecoration(
                  labelText: 'New mobile number',
                  prefixText: '$kPhCountryCode ',
                  errorText: _error,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _sendCode(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : (awaitingCode ? _verify : _sendCode),
          child: Text(awaitingCode ? 'Verify' : 'Send code'),
        ),
      ],
    );
  }
}

class _ChangeEmailDialog extends StatefulWidget {
  const _ChangeEmailDialog({this.currentEmail});

  final String? currentEmail;

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _controller = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _controller.text.trim();
    if (!_emailRegExp.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    if (email.toLowerCase() == widget.currentEmail?.toLowerCase()) {
      setState(() => _error = 'That is already your email');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await AdminAuthService.isEmailTaken(email)) {
        if (mounted) setState(() => _error = 'That email is already in use');
        return;
      }
      await AdminAuthService.requestEmailChange(email);
      if (mounted) {
        Navigator.of(context).pop(
          'Confirmation sent — follow the link in your email to finish the '
          'change.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change email'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We\'ll email a confirmation link. Your email changes once you '
              'follow it. This is also the email you log in to the IsdaSafe '
              'app with.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'New email',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Send link'),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

/// Verifies the admin's phone by SMS code first, and only then offers the
/// new-password form (as in the farmer app). If Supabase also wants a fresh
/// sign-in, it emails a code to enter with the new password.
class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _emailCode = TextEditingController();
  final String? _phone = AdminAuthService.ownProfile.value?.phone;
  var _otpVerified = false;
  var _codeSent = false;
  var _needsEmailCode = false;
  var _obscure = true;
  String? _error;
  var _busy = false;

  String get _maskedPhone {
    final phone = _phone!;
    return phone.length <= 4
        ? phone
        : '${'•' * (phone.length - 4)}${phone.substring(phone.length - 4)}';
  }

  @override
  void initState() {
    super.initState();
    if (_phone == null) {
      _error = 'Add a verified phone number first — we send the code there.';
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
    }
  }

  @override
  void dispose() {
    _otp.dispose();
    _password.dispose();
    _confirm.dispose();
    _emailCode.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminAuthService.sendIdentityOtp();
      if (mounted) setState(() => _codeSent = true);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otp.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminAuthService.verifyPhoneOtp(code);
      if (mounted) setState(() => _otpVerified = true);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!isStrongPassword(_password.text)) {
      setState(() => _error = 'Password doesn\'t meet all the requirements');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords don\'t match');
      return;
    }
    final nonce = _needsEmailCode ? _emailCode.text.trim() : null;
    if (_needsEmailCode && (nonce?.isEmpty ?? true)) {
      setState(() => _error = 'Enter the code we emailed you');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminAuthService.updatePassword(_password.text, nonce: nonce);
      if (mounted) Navigator.of(context).pop('Password updated.');
    } on AuthException catch (e) {
      if (AdminAuthService.needsReauthentication(e) && !_needsEmailCode) {
        try {
          await AdminAuthService.sendReauthenticationCode();
          if (mounted) setState(() => _needsEmailCode = true);
        } catch (e2) {
          if (mounted) setState(() => _error = _errorText(e2));
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _otpStep(ThemeData theme) => [
    Text(
      _phone == null
          ? 'We couldn\'t find a verified phone number on your account.'
          : _codeSent
          ? 'Enter the 6-digit code we texted to $_maskedPhone.'
          : 'Sending a verification code to $_maskedPhone…',
      style: theme.textTheme.bodySmall,
    ),
    const SizedBox(height: AppSpacing.md),
    _CodeField(
      controller: _otp,
      enabled: _codeSent && !_busy,
      error: _error,
      onChanged: () {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: _verifyOtp,
    ),
    if (_phone != null)
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _busy ? null : _sendCode,
          child: const Text('Resend code'),
        ),
      ),
  ];

  List<Widget> _passwordStep(ThemeData theme) => [
    if (_needsEmailCode) ...[
      Text(
        'For your security, we also emailed you a code. Enter it to confirm '
        'the change.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _emailCode,
        enabled: !_busy,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Email code'),
      ),
      const SizedBox(height: AppSpacing.md),
    ],
    Text(
      'This is also the password for the IsdaSafe app if you use the same '
      'account there.',
      style: theme.textTheme.bodySmall,
    ),
    const SizedBox(height: AppSpacing.md),
    TextField(
      controller: _password,
      enabled: !_busy,
      autofocus: !_needsEmailCode,
      obscureText: _obscure,
      autofillHints: const [AutofillHints.newPassword],
      decoration: InputDecoration(
        labelText: 'New password',
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
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
      enabled: !_busy,
      obscureText: _obscure,
      decoration: const InputDecoration(labelText: 'Confirm new password'),
      onChanged: (_) => setState(() => _error = null),
      onSubmitted: (_) => _submit(),
    ),
    if (_error != null) ...[
      const SizedBox(height: AppSpacing.sm),
      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
    ],
  ];

  /// Asks before abandoning the change; closes the dialog on yes.
  Future<void> _confirmCancel() async {
    if (_busy) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_reset),
        title: const Text('Cancel password change?'),
        content: const Text('Your password won\'t be changed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (sure == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: AlertDialog(
        title: Text(_otpVerified ? 'Change password' : 'Verify it’s you'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _otpVerified ? _passwordStep(theme) : _otpStep(theme),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _confirmCancel,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy || (!_otpVerified && !_codeSent)
                ? null
                : (_otpVerified ? _submit : _verifyOtp),
            child: Text(_otpVerified ? 'Update' : 'Verify'),
          ),
        ],
      ),
    );
  }
}
