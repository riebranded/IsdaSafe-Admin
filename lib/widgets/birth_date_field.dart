import 'package:flutter/material.dart';

/// Admins must be at least this old (also enforced by the database).
const kMinAdminAge = 18;

/// Whole years from [birthDate] to [today] (a birthday counts from that
/// day).
int ageOn(DateTime birthDate, DateTime today) {
  var age = today.year - birthDate.year;
  final hadBirthday =
      today.month > birthDate.month ||
      (today.month == birthDate.month && today.day >= birthDate.day);
  if (!hadBirthday) age--;
  return age;
}

/// The error for [birthDate], or null when it's fine.
String? birthDateError(DateTime? birthDate, {DateTime? today}) {
  if (birthDate == null) return 'Enter your date of birth';
  final now = DateUtils.dateOnly(today ?? DateTime.now());
  if (birthDate.isAfter(now)) {
    return 'Your date of birth can\'t be in the future';
  }
  if (ageOn(birthDate, now) < kMinAdminAge) {
    return 'Admins must be at least $kMinAdminAge years old';
  }
  return null;
}

/// "1999-03-04", as the database stores it.
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Date of birth for a [Form]: tap to pick it (or type it in the picker's
/// text mode). Shows the age worked out from it, and an error under
/// [kMinAdminAge].
class BirthDateField extends FormField<DateTime> {
  BirthDateField({
    super.key,
    super.initialValue,
    super.onSaved,
    ValueChanged<DateTime>? onChanged,
    super.enabled,
  }) : super(
         validator: birthDateError,
         builder: (state) => _BirthDateInput(
           state: state,
           enabled: state.widget.enabled,
           onChanged: onChanged,
         ),
       );
}

class _BirthDateInput extends StatelessWidget {
  const _BirthDateInput({
    required this.state,
    required this.enabled,
    required this.onChanged,
  });

  final FormFieldState<DateTime> state;
  final bool enabled;
  final ValueChanged<DateTime>? onChanged;

  Future<void> _pick(BuildContext context) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      helpText: 'Date of birth',
      initialDate:
          state.value ?? DateTime(today.year - 25, today.month, today.day),
      firstDate: DateTime(today.year - 120),
      lastDate: today,
      initialDatePickerMode: DatePickerMode.year,
      fieldLabelText: 'Date of birth',
    );
    if (picked == null) return;
    state.didChange(picked);
    // Show "under 18" straight away rather than on submit.
    state.validate();
    onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = state.value;
    final localizations = MaterialLocalizations.of(context);
    final age = value == null
        ? null
        : ageOn(value, DateUtils.dateOnly(DateTime.now()));

    return Semantics(
      button: true,
      label: 'Date of birth',
      value: value == null ? null : localizations.formatMediumDate(value),
      child: InkWell(
        onTap: enabled ? () => _pick(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          isEmpty: value == null,
          decoration: InputDecoration(
            enabled: enabled,
            labelText: 'Date of birth',
            prefixIcon: const Icon(Icons.cake_outlined),
            suffixIcon: const Icon(Icons.calendar_today_outlined),
            errorText: state.errorText,
            helperText: age == null || state.hasError
                ? 'You must be at least $kMinAdminAge to be an admin'
                : '$age years old',
          ),
          child: value == null
              ? null
              : Text(
                  localizations.formatMediumDate(value),
                  style: theme.textTheme.bodyLarge,
                ),
        ),
      ),
    );
  }
}
