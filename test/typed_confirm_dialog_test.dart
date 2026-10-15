import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafe_admin/widgets/typed_confirm_dialog.dart';

void main() {
  Future<void> open(WidgetTester tester, void Function(bool) onResult) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => onResult(
                await showTypedConfirmDialog(
                  context,
                  title: 'Revoke access?',
                  message: 'They lose access.',
                  phrase: 'REVOKE ACCESS',
                  confirmLabel: 'Revoke',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  FilledButton confirmButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Revoke'));

  testWidgets('the destructive button needs the phrase typed', (tester) async {
    bool? result;
    await open(tester, (r) => result = r);

    expect(find.text('REVOKE ACCESS'), findsWidgets);
    expect(confirmButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'revoke');
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNull);

    // Any case, extra spaces around it are fine.
    await tester.enterText(find.byType(TextField), '  revoke access ');
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('cancelling returns false', (tester) async {
    bool? result;
    await open(tester, (r) => result = r);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
