import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// First name + last name for a [Form]: side by side, stacked on phones.
class NameFields extends StatelessWidget {
  const NameFields({
    super.key,
    required this.firstName,
    required this.lastName,
    this.enabled = true,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController firstName;
  final TextEditingController lastName;
  final bool enabled;
  final bool autofocus;

  /// Called from the last-name field's keyboard action; null moves on to the
  /// next field instead.
  final VoidCallback? onSubmitted;

  static String? _validate(String? value, String what) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Enter your $what';
    if (trimmed.length > 50) return 'Use 50 characters or fewer';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final first = TextFormField(
      controller: firstName,
      enabled: enabled,
      autofocus: autofocus,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.givenName],
      decoration: const InputDecoration(
        labelText: 'First name',
        prefixIcon: Icon(Icons.person_outline),
      ),
      validator: (v) => _validate(v, 'first name'),
    );
    final last = TextFormField(
      controller: lastName,
      enabled: enabled,
      textCapitalization: TextCapitalization.words,
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      autofillHints: const [AutofillHints.familyName],
      decoration: const InputDecoration(labelText: 'Last name'),
      validator: (v) => _validate(v, 'last name'),
      onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
    );

    // Screen width rather than a LayoutBuilder: this also sits in an
    // AlertDialog, which sizes its content intrinsically.
    if (MediaQuery.sizeOf(context).width < 400) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          const SizedBox(height: AppSpacing.md),
          last,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: last),
      ],
    );
  }
}

/// A best guess at (first, last) from a single full name, for pre-filling:
/// the last word is the last name. Empty strings when there's nothing.
({String first, String last}) splitFullName(String? fullName) {
  final words = (fullName ?? '').trim().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return (first: '', last: '');
  if (words.length == 1) return (first: words.single, last: '');
  return (
    first: words.sublist(0, words.length - 1).join(' '),
    last: words.last,
  );
}
