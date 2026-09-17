import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/screens/reset_password_screen.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.light),
    home: child,
  );
}

void main() {
  testWidgets('asks the user to open the email link when there is no recovery session', (tester) async {
    await tester.pumpWidget(
      _wrap(const ResetPasswordScreen(hasRecoverySession: false)),
    );

    expect(find.textContaining('Open the reset link from your email'), findsOneWidget);
    expect(find.text('Old password'), findsNothing);
    expect(find.text('Save password'), findsNothing);
  });

  testWidgets('recovery form sets a new password without asking for the old one', (tester) async {
    String? saved;
    await tester.pumpWidget(
      _wrap(
        ResetPasswordScreen(
          hasRecoverySession: true,
          onSubmit: (password) async => saved = password,
        ),
      ),
    );

    expect(find.text('Old password'), findsNothing);
    expect(find.text('New password (min 8 chars)'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'newpass12');
    await tester.enterText(find.byType(TextField).at(1), 'mismatch1');
    await tester.tap(find.text('Save password'));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(saved, isNull);

    await tester.enterText(find.byType(TextField).at(1), 'newpass12');
    await tester.tap(find.text('Save password'));
    await tester.pump();
    expect(saved, 'newpass12');
  });
}
