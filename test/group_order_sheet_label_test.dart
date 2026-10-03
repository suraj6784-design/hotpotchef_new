import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/widgets/diner_cart_meal_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pumpCartActions(WidgetTester tester, Size surface) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DinerCartMealActions(
              showGroupOrder: true,
              onAddMoreMeals: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('cart action and sheet title read Society/Office HotPOT', (
    tester,
  ) async {
    await pumpCartActions(tester, const Size(360, 800));

    expect(find.text('Add more meals'), findsOneWidget);
    expect(find.text(kSocietyOfficeHotpotLabel), findsOneWidget);
    expect(find.text('Society / office'), findsNothing);
    expect(find.text('Society / office lunch'), findsNothing);

    await tester.tap(find.text(kSocietyOfficeHotpotLabel));
    await tester.pumpAndSettle();

    expect(find.text(kSocietyOfficeHotpotLabel), findsNWidgets(2));
    expect(find.text('Society lunch'), findsOneWidget);
    expect(find.text('Office lunch'), findsOneWidget);
    expect(find.text('Group order'), findsOneWidget);
    expect(find.text('Start society lunch'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Society/Office HotPOT stays visible on a narrow cart', (
    tester,
  ) async {
    await pumpCartActions(tester, const Size(320, 800));

    expect(find.text(kSocietyOfficeHotpotLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
