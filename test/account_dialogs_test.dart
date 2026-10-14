import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafe_admin/services/admin_auth_service.dart';
import 'package:isdasafe_admin/widgets/account_dialogs.dart';

/// A button that opens [open] (so the dialog has a route to pop).
Future<void> _open(
  WidgetTester tester,
  Future<String?> Function(BuildContext) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone dialog checks the number before sending a code', (
    tester,
  ) async {
    await _open(
      tester,
      (c) => showChangePhoneDialog(c, currentPhone: '+639171234567'),
    );
    expect(find.text('Change phone number'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12345');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(
      find.text('Enter a valid mobile number (e.g. 917 123 4567)'),
      findsOneWidget,
    );

    // A leading 0 is dropped as it's typed; the same number is refused.
    await tester.enterText(find.byType(TextField), '09171234567');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('That is already your number'), findsOneWidget);
  });

  testWidgets('email dialog checks the address before sending a link', (
    tester,
  ) async {
    await _open(
      tester,
      (c) => showChangeEmailDialog(c, currentEmail: 'admin@example.com'),
    );
    expect(find.text('Change email'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Send link'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Admin@Example.com');
    await tester.tap(find.text('Send link'));
    await tester.pump();
    expect(find.text('That is already your email'), findsOneWidget);
  });

  testWidgets('password dialog needs a verified phone and confirms cancel', (
    tester,
  ) async {
    AdminAuthService.ownProfile.value = null;
    await _open(tester, showChangePasswordDialog);

    expect(find.text('Verify it’s you'), findsOneWidget);
    expect(
      find.text('Add a verified phone number first — we send the code there.'),
      findsOneWidget,
    );
    // Verify stays off until a code is sent.
    final verify = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Verify'),
    );
    expect(verify.onPressed, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel password change?'), findsOneWidget);
    await tester.tap(find.text('Yes, cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Verify it’s you'), findsNothing);
  });
}
