import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafe_admin/widgets/name_fields.dart';

void main() {
  test('splitFullName takes the last word as the last name', () {
    expect(splitFullName('Juan dela Cruz'), (first: 'Juan dela', last: 'Cruz'));
    expect(splitFullName('  Maria   Santos '), (
      first: 'Maria',
      last: 'Santos',
    ));
    expect(splitFullName('Cher'), (first: 'Cher', last: ''));
    expect(splitFullName(null), (first: '', last: ''));
  });

  for (final width in const [1200.0, 390.0]) {
    testWidgets('works inside a dialog at ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final formKey = GlobalKey<FormState>();
      final first = TextEditingController();
      final last = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: AlertDialog(
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: NameFields(firstName: first, lastName: last),
              ),
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Enter your first name'), findsOneWidget);
      expect(find.text('Enter your last name'), findsOneWidget);

      first.text = 'Juan';
      last.text = 'dela Cruz';
      expect(formKey.currentState!.validate(), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
