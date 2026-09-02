import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/app_theme.dart';
import 'package:hotpotchef_new/widgets/meal_review_dialog.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('review dialog uses light surface and dark title in light theme', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MealReviewDialog(
          mealTitle: 'Dal Tadka',
          onSubmit: (_, __) async {},
        ),
      ),
    );

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, AppTheme.surfaceLight);

    final title = tester.widget<Text>(find.text('Rate Dal Tadka'));
    expect(title.style?.color, AppTheme.textMain);
    expect(find.text('How was the food from this home kitchen?'), findsOneWidget);
  });

  testWidgets('review dialog uses dark surface and light title in dark theme', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MealReviewDialog(
          mealTitle: 'Dal Tadka',
          onSubmit: (_, __) async {},
        ),
        brightness: Brightness.dark,
      ),
    );

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, AppTheme.surfaceDark);

    final title = tester.widget<Text>(find.text('Rate Dal Tadka'));
    expect(title.style?.color, AppTheme.textMainDark);
  });

  testWidgets('Skip closes without submitting', (tester) async {
    var submitted = false;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showDialog<bool>(
                context: context,
                builder: (_) => MealReviewDialog(
                  mealTitle: 'Rice',
                  onSubmit: (_, __) async => submitted = true,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(submitted, isFalse);
    expect(find.byType(MealReviewDialog), findsNothing);
  });
}
