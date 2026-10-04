import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotpotchef_new/utils/meal_occasions.dart';
import 'package:hotpotchef_new/widgets/home_occasion_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('home opens on Everyday and Ask kitchens follows the selected tab', (tester) async {
    var occasion = kOccasionEveryday;
    var slice = kOccasionSliceAll;
    String? asked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return HomeOccasionBar(
                occasion: occasion,
                slice: slice,
                onOccasion: (id) => setState(() {
                  occasion = id;
                  slice = kOccasionSliceAll;
                }),
                onSlice: (id) => setState(() => slice = id),
                onBroadcast: () => asked = '$occasion:$slice',
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Everyday'), findsOneWidget);
    expect(find.text('Festivals'), findsOneWidget);
    expect(find.text('Parties'), findsOneWidget);
    expect(find.text('Specialty'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Diwali'), findsNothing);
    expect(find.text('Ask kitchens'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-occasion-party')));
    await tester.pumpAndSettle();
    expect(find.text('Birthday'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);

    await tester.tap(find.byKey(const Key('home-occasion-slice-birthday')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-occasion-broadcast')));
    await tester.pump();

    expect(asked, 'party:birthday');

    await tester.tap(find.byKey(const Key('home-occasion-specialty')));
    await tester.pumpAndSettle();
    expect(find.text('Pickles'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-occasion-broadcast')));
    expect(asked, 'specialty:all');
  });
}
