// Widget smoke test for a self-contained UI component.
//
// The full app (`HotPotChefApp`) requires Firebase and Supabase to be
// initialized in `main()`, so it is not suitable for a lightweight widget
// test. Instead we verify a pure, dependency-free widget renders correctly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hotpotchef_new/widgets/app_status_badge.dart';

void main() {
  testWidgets('AppStatusBadge renders its status label', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppStatusBadge(status: 'Pending'),
          ),
        ),
      ),
    );

    expect(find.text('Pending'), findsOneWidget);
    expect(find.byType(AppStatusBadge), findsOneWidget);
  });

  testWidgets('AppStatusBadge renders in dark theme without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: Center(
            child: AppStatusBadge(status: 'Out for delivery'),
          ),
        ),
      ),
    );

    expect(find.text('Out for delivery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
