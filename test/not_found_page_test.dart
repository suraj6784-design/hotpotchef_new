import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/app_theme.dart';
import 'package:hotpotchef_new/widgets/not_found_page.dart';

void main() {
  testWidgets('404 page uses light background and dark title in light theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: NotFoundPage(onHome: () {}),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTheme.background);
    final title = tester.widget<Text>(find.text('Page not found'));
    expect(title.style?.color, AppTheme.textMain);
    expect(find.text('Return Home'), findsOneWidget);
  });

  testWidgets('404 page uses dark background and light title in dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: NotFoundPage(onHome: () {}),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTheme.backgroundDark);
    final title = tester.widget<Text>(find.text('Page not found'));
    expect(title.style?.color, AppTheme.textMainDark);
  });

  testWidgets('Return Home runs the callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NotFoundPage(onHome: () => tapped = true),
      ),
    );

    await tester.tap(find.text('Return Home'));
    expect(tapped, isTrue);
  });
}
