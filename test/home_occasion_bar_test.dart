import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotpotchef_new/utils/app_theme.dart';
import 'package:hotpotchef_new/utils/meal_occasions.dart';
import 'package:hotpotchef_new/widgets/diner_home_plate_card.dart';
import 'package:hotpotchef_new/widgets/diner_storefront.dart';
import 'package:hotpotchef_new/widgets/home_occasion_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('home opens on Everyday and Ask kitchens follows the selected tab', (tester) async {
    var occasion = kOccasionEveryday;
    var slice = kOccasionSliceAll;
    String? asked;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    final everyday = tester.getRect(find.byKey(const Key('home-occasion-everyday')));
    final festivals = tester.getRect(find.byKey(const Key('home-occasion-festive')));
    final parties = tester.getRect(find.byKey(const Key('home-occasion-party')));
    final specialty = tester.getRect(find.byKey(const Key('home-occasion-specialty')));
    expect(everyday.top, festivals.top);
    expect(festivals.top, parties.top);
    expect(parties.top, specialty.top);
    expect(everyday.height, greaterThanOrEqualTo(48));
    expect(specialty.right, lessThanOrEqualTo(tester.view.physicalSize.width / tester.view.devicePixelRatio + 1));

    final slices = tester.getRect(find.byKey(const Key('home-occasion-slice-all')));
    expect(slices.top, greaterThan(everyday.bottom));
    expect(slices.height, lessThan(everyday.height));
    final ask = tester.getRect(find.byKey(const Key('home-occasion-broadcast')));
    expect(ask.top, greaterThan(slices.bottom - 1));
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

  testWidgets('order timing stays above the occasion row and does not change it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var mode = 'preorder';
    var occasion = kOccasionEveryday;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor: AppTheme.background,
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HomeOrderModeBar(
                  mode: mode,
                  onChanged: (value) {
                    mode = value;
                  },
                ),
                HomeOccasionBar(
                  occasion: occasion,
                  slice: kOccasionSliceAll,
                  onOccasion: (id) => occasion = id,
                  onSlice: (_) {},
                  onBroadcast: () {},
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: DinerHomePlateCard(
                    title: 'Veg Jumbo Thali',
                    chefName: 'by Newchef16',
                    priceLabel: '₹221',
                    prepMinutes: 30,
                    portionsLabel: '4 left',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final timing = tester.getRect(find.byKey(const Key('home-order-mode-preorder')));
    final everyday = tester.getRect(find.byKey(const Key('home-occasion-everyday')));
    final plate = tester.getRect(find.text('Veg Jumbo Thali'));
    expect(timing.bottom, lessThan(everyday.top));
    expect(plate.top, greaterThan(everyday.bottom));
    expect(find.textContaining('30 min'), findsOneWidget);
    expect(find.textContaining('4 left'), findsOneWidget);
    expect(find.text('₹221'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-order-mode-live')));
    await tester.pump();
    expect(mode, 'live');
    expect(occasion, kOccasionEveryday);
  });
}
