import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Admin numbers are Philippine mobiles, like the farmer app's: the calling
/// code is fixed and the field takes the 10 digits after it.
const kPhCountryCode = '+63';

/// "09171234567" is how PH numbers are usually typed, but E.164 drops the
/// trunk 0 ("+639171234567"), so a leading 0 is stripped as it's typed.
class _StripLeadingTrunkZeroFormatter extends TextInputFormatter {
  const _StripLeadingTrunkZeroFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.startsWith('0')) return newValue;
    final stripped = newValue.text.substring(1);
    final offset = (newValue.selection.baseOffset - 1).clamp(
      0,
      stripped.length,
    );
    return TextEditingValue(
      text: stripped,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

final _localDigitsRegExp = RegExp(r'^9\d{9}$');

/// The E.164 number for the field's digits, e.g. "+639171234567".
String toE164Phone(String localDigits) =>
    '$kPhCountryCode${localDigits.trim()}';

/// The field's digits for an E.164 number (the reverse of [toE164Phone]).
String toLocalPhoneDigits(String? e164) =>
    (e164 ?? '').startsWith(kPhCountryCode)
    ? e164!.substring(kPhCountryCode.length)
    : '';

/// Mobile-number field with the fixed +63 prefix. The number receives the
/// admin's OTP codes; it may be the same as a farmer account's number.
class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.helperText = 'Used to send your verification codes (OTP)',
  });

  final TextEditingController controller;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.phone,
      textInputAction: textInputAction,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        const _StripLeadingTrunkZeroFormatter(),
        LengthLimitingTextInputFormatter(10),
      ],
      decoration: InputDecoration(
        labelText: 'Mobile number',
        hintText: '9171234567',
        prefixIcon: const Icon(Icons.phone_outlined),
        prefixText: '$kPhCountryCode ',
        helperText: helperText,
      ),
      validator: (value) {
        final digits = value?.trim() ?? '';
        if (digits.isEmpty) return 'Enter your mobile number';
        if (!_localDigitsRegExp.hasMatch(digits)) {
          return 'Enter a valid PH mobile number (e.g. 9171234567)';
        }
        return null;
      },
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}
