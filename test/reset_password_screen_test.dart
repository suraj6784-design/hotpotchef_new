import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hotpotchef_new/screens/reset_password_screen.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('Validators.confirmPassword', () {
    test('requires a matching confirmation', () {
      expect(Validators.password('short'), isNotNull);
      expect(Validators.password('longenough'), isNull);
      expect(Validators.confirmPassword(null, 'longenough'), isNotNull);
      expect(Validators.confirmPassword('otherpass', 'longenough'), isNotNull);
      expect(Validators.confirmPassword('longenough', 'longenough'), isNull);
    });
  });

  testWidgets('shows validation errors for a short or mismatched password', (
    tester,
  ) async {
    await tester.pumpWidget(_resetHarness(updatePassword: (_) async {}));

    await tester.tap(find.text('Update password'));
    await tester.pump();
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'longenough');
    await tester.enterText(find.byType(TextFormField).at(1), 'different1');
    await tester.tap(find.text('Update password'));
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('submits a valid password and continues to the hub', (
    tester,
  ) async {
    String? submitted;
    final router = _resetRouter(
      updatePassword: (password) async {
        submitted = password;
      },
      hubLocation: () => '/customer-hub',
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.enterText(find.byType(TextFormField).at(0), 'longenough');
    await tester.enterText(find.byType(TextFormField).at(1), 'longenough');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(submitted, 'longenough');
    expect(find.text('customer-hub'), findsOneWidget);
  });

  testWidgets('shows an error when password update fails', (tester) async {
    await tester.pumpWidget(
      _resetHarness(
        updatePassword: (_) async {
          throw Exception('session expired');
        },
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'longenough');
    await tester.enterText(find.byType(TextFormField).at(1), 'longenough');
    await tester.tap(find.text('Update password'));
    await tester.pump();

    expect(find.textContaining('Could not update password'), findsOneWidget);
    expect(find.textContaining('session expired'), findsOneWidget);
    expect(find.text('Set a new password'), findsOneWidget);
  });
}

Widget _resetHarness({
  required Future<void> Function(String password) updatePassword,
}) {
  return MaterialApp.router(
    routerConfig: _resetRouter(updatePassword: updatePassword),
  );
}

GoRouter _resetRouter({
  required Future<void> Function(String password) updatePassword,
  String Function()? hubLocation,
}) {
  return GoRouter(
    initialLocation: '/reset-password',
    routes: [
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => ResetPasswordScreen(
          updatePassword: updatePassword,
          hubLocation: hubLocation ?? () => '/customer-hub',
        ),
      ),
      GoRoute(
        path: '/customer-hub',
        builder: (context, state) => const Scaffold(body: Text('customer-hub')),
      ),
    ],
  );
}
