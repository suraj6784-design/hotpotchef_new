import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/widgets/diner_feed_empty.dart';
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

  testWidgets('empty Festivals keeps the four buttons and asks kitchens for that selection', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final copy = feedEmptyCopy(
      signedIn: true,
      favoritesOnly: false,
      hasFavorites: false,
      hasSearch: false,
      hasDeliveryPin: true,
      occasion: kOccasionFestive,
      occasionSlice: kOccasionSliceAll,
    );
    expect(dinerFeedEmptyAction(copy), DinerFeedEmptyAction.askKitchens);
    expect(dinerFeedEmptyActionLabel(DinerFeedEmptyAction.askKitchens), 'Ask kitchens');

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            backgroundColor: AppTheme.background,
            body: ListView(
              children: [
                HomeOccasionBar(
                  occasion: kOccasionFestive,
                  slice: kOccasionSliceAll,
                  onOccasion: (_) {},
                  onSlice: (_) {},
                  onBroadcast: () => pushAskKitchens(
                    context,
                    occasion: kOccasionFestive,
                    slice: kOccasionSliceAll,
                  ),
                ),
                DinerFeedEmpty(
                  copy: copy,
                  showFollowing: false,
                  showFavorites: false,
                  onAskKitchens: () => pushAskKitchens(
                    context,
                    occasion: kOccasionFestive,
                    slice: kOccasionSliceAll,
                  ),
                  onSignIn: () {},
                  onClearFilters: () {},
                  onPreorder: () {},
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/bulk-request',
          builder: (_, state) {
            final occasion = state.uri.queryParameters['occasion'];
            final slice = state.uri.queryParameters['slice'];
            return Scaffold(body: Text('ask:$occasion:$slice'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Everyday'), findsOneWidget);
    expect(find.text('Festivals'), findsOneWidget);
    expect(find.text('Parties'), findsOneWidget);
    expect(find.text('Specialty'), findsOneWidget);
    expect(find.text('No Festivals meals'), findsOneWidget);
    expect(find.textContaining('tab'), findsNothing);
    expect(find.text('Nothing in Festivals is on the menu for this pin. Try another occasion.'), findsOneWidget);
    expect(find.byKey(const Key('home-occasion-empty-ask')), findsOneWidget);

    final everyday = tester.getRect(find.byKey(const Key('home-occasion-everyday')));
    final festivals = tester.getRect(find.byKey(const Key('home-occasion-festive')));
    expect(everyday.top, festivals.top);

    await tester.tap(find.byKey(const Key('home-occasion-empty-ask')));
    await tester.pumpAndSettle();
    expect(find.text('ask:festive:all'), findsOneWidget);
  });

  testWidgets('an empty party slice prefills Ask kitchens with that slice', (tester) async {
    final copy = feedEmptyCopy(
      signedIn: true,
      favoritesOnly: false,
      hasFavorites: false,
      hasSearch: false,
      hasDeliveryPin: true,
      occasion: kOccasionParty,
      occasionSlice: 'birthday',
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: DinerFeedEmpty(
              copy: copy,
              showFollowing: false,
              showFavorites: false,
              onAskKitchens: () => pushAskKitchens(
                context,
                occasion: kOccasionParty,
                slice: 'birthday',
              ),
              onSignIn: () {},
              onClearFilters: () {},
              onPreorder: () {},
            ),
          ),
        ),
        GoRoute(
          path: '/bulk-request',
          builder: (_, state) => Scaffold(
            body: Text('ask:${state.uri.queryParameters['occasion']}:${state.uri.queryParameters['slice']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('No Birthday meals'), findsOneWidget);
    expect(find.textContaining('tab'), findsNothing);
    await tester.tap(find.byKey(const Key('home-occasion-empty-ask')));
    await tester.pumpAndSettle();
    expect(find.text('ask:party:birthday'), findsOneWidget);
  });
}
