import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafe_admin/widgets/birth_date_field.dart';

void main() {
  group('ageOn', () {
    final today = DateTime(2026, 10, 14);

    test('counts a birthday from that day', () {
      expect(ageOn(DateTime(2008, 10, 14), today), 18);
      expect(ageOn(DateTime(2008, 10, 15), today), 17);
      expect(ageOn(DateTime(1990, 1, 1), today), 36);
    });

    test('handles a 29 February birthday', () {
      expect(ageOn(DateTime(2008, 2, 29), DateTime(2026, 2, 28)), 17);
      expect(ageOn(DateTime(2008, 2, 29), DateTime(2026, 3, 1)), 18);
    });
  });

  group('birthDateError', () {
    final today = DateTime(2026, 10, 14);

    test('requires a date', () {
      expect(birthDateError(null, today: today), 'Enter your date of birth');
    });

    test('refuses anyone under 18', () {
      expect(
        birthDateError(DateTime(2008, 10, 15), today: today),
        'Admins must be at least 18 years old',
      );
      expect(birthDateError(DateTime(2008, 10, 14), today: today), isNull);
    });

    test('refuses a future date', () {
      expect(
        birthDateError(DateTime(2027, 1, 1), today: today),
        'Your date of birth can\'t be in the future',
      );
    });
  });

  Future<GlobalKey<FormState>> pumpField(
    WidgetTester tester,
    DateTime? initial,
  ) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: BirthDateField(initialValue: initial),
          ),
        ),
      ),
    );
    return formKey;
  }

  testWidgets('shows the age worked out from the date', (tester) async {
    final now = DateTime.now();
    await pumpField(tester, DateTime(now.year - 30, 1, 1));
    expect(find.text('30 years old'), findsOneWidget);
  });

  testWidgets('shows the under-18 error', (tester) async {
    final now = DateTime.now();
    final formKey = await pumpField(tester, DateTime(now.year - 16, 1, 1));
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Admins must be at least 18 years old'), findsOneWidget);
  });

  testWidgets('tapping opens a date picker', (tester) async {
    await pumpField(tester, null);
    await tester.tap(find.text('Date of birth'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}
