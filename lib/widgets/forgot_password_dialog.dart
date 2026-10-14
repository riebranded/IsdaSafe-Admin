import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_auth_service.dart';
import 'captcha_field.dart';

/// Resets a forgotten password in two steps, like the farmer app: enter the
/// email (a one-time code is sent), then enter that code. A correct code
/// opens a recovery session and AdminGate shows the set-new-password screen.
/// Returns true once the code is verified, or null if cancelled.
Future<bool?> showForgotPasswordDialog(
  BuildContext context, {
  String initialEmail = '',
}) {
  final email = TextEditingController(text: initialEmail);
  final code = TextEditingController();
  final captchaKey = GlobalKey<CaptchaFieldState>();

  return showDialog<bool>(
    context: context,
    builder: (context) {
      String? errorText;
      String? captchaToken;
      var codeSent = false;
      var isSubmitting = false;

      return StatefulBuilder(
        builder: (context, setState) {
          void fail(String message) => setState(() {
            isSubmitting = false;
            errorText = message;
          });

          void clearError() {
            if (errorText != null) setState(() => errorText = null);
          }

          Future<void> sendCode() async {
            final address = email.text.trim();
            if (address.isEmpty || !address.contains('@')) {
              setState(() => errorText = 'Enter a valid email address');
              return;
            }
            final token = captchaToken;
            if (token == null) return;

            setState(() => isSubmitting = true);
            try {
              await AdminAuthService.sendPasswordResetCode(
                address,
                captchaToken: token,
              );
              setState(() {
                isSubmitting = false;
                codeSent = true;
                errorText = null;
              });
            } on AuthException catch (e) {
              fail(e.message);
            } catch (e) {
              fail('Something went wrong. Please try again.');
              debugPrint('showForgotPasswordDialog: error $e');
            } finally {
              // Tokens are single-use — always fetch a fresh one.
              captchaKey.currentState?.reset();
            }
          }

          Future<void> verify() async {
            final entered = code.text.trim();
            if (entered.length < 6) {
              setState(() => errorText = 'Enter the code from the email');
              return;
            }
            setState(() => isSubmitting = true);
            final navigator = Navigator.of(context);
            try {
              await AdminAuthService.verifyRecoveryCode(
                email.text.trim(),
                entered,
              );
              navigator.pop(true);
            } on AuthException catch (e) {
              fail(e.message);
            } catch (e) {
              fail('Something went wrong. Please try again.');
              debugPrint('showForgotPasswordDialog: verify error $e');
            }
          }

          return AlertDialog(
            title: Text(
              codeSent ? 'Enter the code' : 'Reset your password',
              textAlign: TextAlign.center,
            ),
            content: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: codeSent
                      ? [
                          Text(
                            'We sent a 6-digit code to ${email.text.trim()}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: code,
                            autofocus: true,
                            enabled: !isSubmitting,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(
                              fontSize: 24,
                              letterSpacing: 6,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: '••••••',
                              errorText: errorText,
                            ),
                            onChanged: (_) => clearError(),
                            onSubmitted: (_) => verify(),
                          ),
                        ]
                      : [
                          TextField(
                            controller: email,
                            autofocus: true,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            enabled: !isSubmitting,
                            decoration: InputDecoration(
                              labelText: 'Email address',
                              errorText: errorText,
                            ),
                            onChanged: (_) => clearError(),
                            onSubmitted: (_) => sendCode(),
                          ),
                          const SizedBox(height: 12),
                          CaptchaField(
                            key: captchaKey,
                            onTokenChanged: (token) =>
                                setState(() => captchaToken = token),
                          ),
                        ],
                ),
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : codeSent
                    ? verify
                    : (captchaToken == null ? null : sendCode),
                child: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(codeSent ? 'Verify code' : 'Send code'),
              ),
            ],
          );
        },
      );
    },
  );
}
