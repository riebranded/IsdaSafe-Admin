import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'password_strength_checklist.dart';

/// Password + live requirement checklist + confirmation, for setting a new
/// password inside a [Form] (the request-access and phone-verification
/// screens). Read the password from [controller].
class NewPasswordFields extends StatefulWidget {
  const NewPasswordFields({
    super.key,
    required this.controller,
    this.enabled = true,
    this.helperText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? helperText;
  final VoidCallback? onSubmitted;

  @override
  State<NewPasswordFields> createState() => _NewPasswordFieldsState();
}

class _NewPasswordFieldsState extends State<NewPasswordFields> {
  final _confirm = TextEditingController();
  var _obscure = true;
  var _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _confirm.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Widget _visibilityToggle(bool obscured, VoidCallback onPressed) => IconButton(
    icon: Icon(
      obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
    ),
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: _obscure,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: widget.helperText,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: _visibilityToggle(
              _obscure,
              () => setState(() => _obscure = !_obscure),
            ),
          ),
          validator: (value) => isStrongPassword(value ?? '')
              ? null
              : 'Password doesn\'t meet all the requirements',
        ),
        const SizedBox(height: AppSpacing.sm),
        PasswordStrengthChecklist(password: widget.controller.text),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _confirm,
          enabled: widget.enabled,
          obscureText: _obscureConfirm,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: _visibilityToggle(
              _obscureConfirm,
              () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          validator: (value) =>
              value != widget.controller.text ? 'Passwords don\'t match' : null,
          onFieldSubmitted: (_) => widget.onSubmitted?.call(),
        ),
      ],
    );
  }
}
