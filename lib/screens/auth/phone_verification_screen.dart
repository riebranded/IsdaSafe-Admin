import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin_auth_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/auth_layout.dart';
import '../../widgets/new_password_fields.dart';
import '../../widgets/phone_input.dart';

/// Shown by AdminGate until the admin's mobile number is verified: texts a
/// code to it and checks it. The number can be one a farmer account already
/// uses; only another verified admin's number is refused.
///
/// An admin with no number on file (one from before numbers were asked at
/// sign-up) also sets a password here, as new sign-ups do.
class PhoneVerificationScreen extends StatefulWidget {
  const PhoneVerificationScreen({
    super.key,
    required this.initialPhone,
    required this.onVerified,
  });

  /// The number given at sign-up (E.164), or null for an admin who never
  /// gave one — they're asked for it, and a password, first.
  final String? initialPhone;
  final VoidCallback onVerified;

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  /// Matches send-semaphore-otp's per-user cooldown.
  static const _resendCooldown = 60;

  final _phoneFormKey = GlobalKey<FormState>();
  late final _phone = TextEditingController(
    text: toLocalPhoneDigits(widget.initialPhone),
  );
  final _code = TextEditingController();
  final _password = TextEditingController();

  /// Until the password is saved; it isn't asked again on a resend.
  late var _needsPassword = widget.initialPhone == null;

  late var _editingPhone = widget.initialPhone == null;
  var _codeSent = false;
  var _busy = false;
  var _secondsLeft = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendCooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsLeft <= 1) {
        timer.cancel();
        if (mounted) setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _sendCode() async {
    if (_editingPhone && !(_phoneFormKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (_needsPassword) {
        await AdminAuthService.updatePassword(_password.text);
        if (!mounted) return;
        setState(() => _needsPassword = false);
      }
      await AdminAuthService.sendPhoneOtp(toE164Phone(_phone.text));
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _editingPhone = false;
        _code.clear();
      });
      _startCooldown();
    } on AuthException catch (e) {
      if (mounted) _showMessage(e.message);
    } on PostgrestException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (e) {
      debugPrint('PhoneVerificationScreen: send error $e');
      if (mounted) _showMessage('Couldn\'t send the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 4) {
      _showMessage('Enter the code we texted you.');
      return;
    }
    setState(() => _busy = true);
    try {
      await AdminAuthService.verifyPhoneOtp(code);
      widget.onVerified();
    } on AuthException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (e) {
      debugPrint('PhoneVerificationScreen: verify error $e');
      if (mounted) _showMessage('Couldn\'t check the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      builder: (context, isWide) {
        final theme = Theme.of(context);
        final phone = '$kPhCountryCode ${_phone.text}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phone_iphone_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _needsPassword
                  ? 'Add your mobile number and a password'
                  : 'Verify your mobile number',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _editingPhone
                  ? 'Your verification codes (OTP) are sent to this number. '
                        'It can be the same one you use in the IsdaSafe app.'
                  : _codeSent
                  ? 'Enter the code we texted to $phone.'
                  : 'We\'ll text a verification code to $phone.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_editingPhone)
              Form(
                key: _phoneFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhoneNumberField(
                      controller: _phone,
                      enabled: !_busy,
                      helperText: null,
                      textInputAction: _needsPassword
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: _needsPassword
                          ? null
                          : (_) => _sendCode(),
                    ),
                    if (_needsPassword) ...[
                      const SizedBox(height: AppSpacing.md),
                      NewPasswordFields(
                        controller: _password,
                        enabled: !_busy,
                        helperText: 'For logging in with your email',
                        onSubmitted: _sendCode,
                      ),
                    ],
                  ],
                ),
              )
            else if (_codeSent)
              TextField(
                controller: _code,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                style: theme.textTheme.headlineSmall?.copyWith(
                  letterSpacing: 8,
                ),
                decoration: const InputDecoration(labelText: 'Code'),
                onSubmitted: (_) => _verify(),
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_codeSent ? 'Verify' : 'Send code'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: (_busy || _secondsLeft > 0) ? null : _sendCode,
                child: Text(
                  _secondsLeft > 0
                      ? 'Resend code in ${_secondsLeft}s'
                      : 'Resend code',
                ),
              ),
            if (!_editingPhone)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _editingPhone = true;
                        _codeSent = false;
                      }),
                child: const Text('Use a different number'),
              ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: _busy ? null : AdminAuthService.signOut,
              child: const Text('Sign out'),
            ),
          ],
        );
      },
    );
  }
}
