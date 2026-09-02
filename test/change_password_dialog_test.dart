import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/app_theme.dart';
import 'package:hotpotchef_new/widgets/change_password_dialog.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('change password dialog uses light surface in light theme', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChangePasswordDialog(
          requireConfirm: true,
          onSubmit: ({currentPassword, required newPassword}) async {},
        ),
      ),
    );

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, AppTheme.surfaceLight);
    final title = tester.widget<Text>(find.text('Change Password'));
    expect(title.style?.color, AppTheme.textMain);
  });

  testWidgets('change password dialog uses dark surface in dark theme', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChangePasswordDialog(
          requireCurrentPassword: true,
          onSubmit: ({currentPassword, required newPassword}) async {},
        ),
        brightness: Brightness.dark,
      ),
    );

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, AppTheme.surfaceDark);
    final title = tester.widget<Text>(find.text('Change Password'));
    expect(title.style?.color, AppTheme.textMainDark);
    expect(find.text('Current password'), findsOneWidget);
  });

  testWidgets('shows an error when the new password is too short', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChangePasswordDialog(
          onSubmit: ({currentPassword, required newPassword}) async {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'short');
    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(find.text('Password must be at least 8 characters long.'), findsOneWidget);
  });
}
