import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/widgets/app_widgets.dart';
import 'package:hotpotchef_new/widgets/diner_feed_empty.dart';
import 'package:hotpotchef_new/widgets/diner_storefront.dart';
import 'package:hotpotchef_new/widgets/home_occasion_bar.dart';

/// Android Studio "Medium Phone": 1080x2400 at 420dpi.
/// Logical size is about 411 x 914. Three-button navigation (48dp) plus the
/// hub dock (80 + that inset) is the tighter fold the empty Ask kitchens
/// button missed by a short scroll.
const _mediumPhoneDpr = 420 / 160;
const _mediumPhoneHeightPx = 2400.0;
const _statusBarDp = 24.0;
const _threeButtonNavDp = 48.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final sample in const [
    (
      label: 'Festivals',
      widthDp: 1080 / _mediumPhoneDpr,
      occasion: kOccasionFestive,
      slice: kOccasionSliceAll,
    ),
    (
      label: 'Festivals 390',
      widthDp: 390.0,
      occasion: kOccasionFestive,
      slice: kOccasionSliceAll,
    ),
    (
      label: 'Christmas',
      widthDp: 390.0,
      occasion: kOccasionFestive,
      slice: 'christmas',
    ),
    (
      label: 'Parties',
      widthDp: 412.0,
      occasion: kOccasionParty,
      slice: kOccasionSliceAll,
    ),
    (
      label: 'Anniversary',
      widthDp: 390.0,
      occasion: kOccasionParty,
      slice: 'anniversary',
    ),
    (
      label: 'Specialty',
      widthDp: 412.0,
      occasion: kOccasionSpecialty,
      slice: kOccasionSliceAll,
    ),
    (
      label: 'Seasonal jars',
      widthDp: 390.0,
      occasion: kOccasionSpecialty,
      slice: 'seasonal',
    ),
  ]) {
    testWidgets(
      'empty ${sample.label} Ask kitchens sits above the Medium Phone fold',
      (tester) async {
        final copy = await _pumpHomeEmpty(
          tester,
          widthDp: sample.widthDp,
          occasion: sample.occasion,
          slice: sample.slice,
        );

        final viewport = tester.getRect(find.byType(SingleChildScrollView));
        final cta = tester.getRect(
          find.byKey(const Key('home-occasion-empty-ask')),
        );
        expect(cta.top, greaterThanOrEqualTo(viewport.top));
        expect(cta.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(find.text(copy.title), findsOneWidget);
        expect(find.text(copy.message), findsOneWidget);
        expect(find.byType(GradientButton), findsOneWidget);
        expect(find.text('Ask kitchens'), findsNWidgets(2));

        for (final id in const ['everyday', 'festive', 'party', 'specialty']) {
          final button = tester.getRect(find.byKey(Key('home-occasion-$id')));
          expect(button.top, greaterThanOrEqualTo(viewport.top));
          expect(button.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(button.height, greaterThanOrEqualTo(48));
        }
      },
    );
  }

  testWidgets('Everyday empty keeps the roomy empty state', (tester) async {
    final copy = await _pumpHomeEmpty(
      tester,
      widthDp: 1080 / _mediumPhoneDpr,
      occasion: kOccasionEveryday,
      slice: 'lunch',
    );

    expect(copy.title, 'No Lunch meals');
    expect(find.byKey(const Key('home-occasion-empty-ask')), findsNothing);
    expect(find.text('Show all meals'), findsOneWidget);
    final paddings = tester.widgetList<Padding>(
      find.ancestor(
        of: find.text('No Lunch meals'),
        matching: find.byType(Padding),
      ),
    );
    expect(
      paddings.map((padding) => padding.padding),
      contains(const EdgeInsets.all(32)),
    );
  });
}

Future<FeedEmptyCopy> _pumpHomeEmpty(
  WidgetTester tester, {
  required double widthDp,
  required String occasion,
  required String slice,
}) async {
  tester.view.devicePixelRatio = _mediumPhoneDpr;
  tester.view.physicalSize = Size(
    widthDp * _mediumPhoneDpr,
    _mediumPhoneHeightPx,
  );
  tester.view.viewPadding = const FakeViewPadding(
    left: 0,
    top: _statusBarDp * _mediumPhoneDpr,
    right: 0,
    bottom: _threeButtonNavDp * _mediumPhoneDpr,
  );
  tester.view.padding = const FakeViewPadding(
    left: 0,
    top: _statusBarDp * _mediumPhoneDpr,
    right: 0,
    bottom: _threeButtonNavDp * _mediumPhoneDpr,
  );
  addTearDown(tester.view.reset);

  final copy = feedEmptyCopy(
    signedIn: true,
    favoritesOnly: false,
    hasFavorites: false,
    hasSearch: false,
    hasDeliveryPin: true,
    occasion: occasion,
    occasionSlice: slice,
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        backgroundColor: AppTheme.background,
        body: Builder(
          builder: (context) {
            return Padding(
              padding: EdgeInsets.only(bottom: hubDockBodyGap(context)),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _homeHeader(context),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 12, 20, 14),
                      child: SizedBox(height: 52),
                    ),
                    HomeOrderModeBar(mode: 'preorder', onChanged: (_) {}),
                    HomeOccasionBar(
                      occasion: occasion,
                      slice: slice,
                      onOccasion: (_) {},
                      onSlice: (_) {},
                      onBroadcast: () {},
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(height: 40),
                    const SizedBox(height: 8),
                    const SizedBox(height: 12),
                    DinerFeedEmpty(
                      copy: copy,
                      showFollowing: false,
                      showFavorites: false,
                      onAskKitchens: () {},
                      onSignIn: () {},
                      onClearFilters: () {},
                      onPreorder: () {},
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return copy;
}

/// Same header stack as diner home: logo row, greeting, delivery pin.
Widget _homeHeader(BuildContext context) {
  return Container(
    width: double.infinity,
    color: AppTheme.canvasOf(context),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const AppLogo(size: 28),
                const SizedBox(width: 8),
                Text(
                  'HotPotChef',
                  style: AppTheme.sectionTitleOf(
                    context,
                  ).copyWith(color: AppTheme.primary, fontSize: 18),
                ),
                const Spacer(),
                for (final icon in const [
                  Icons.storefront_outlined,
                  Icons.favorite_border,
                  Icons.shopping_bag_outlined,
                ])
                  IconButton(
                    onPressed: () {},
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(36, 36),
                      maximumSize: const Size(36, 36),
                      padding: EdgeInsets.zero,
                    ),
                    icon: Icon(icon, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Good evening', style: AppTheme.sectionTitleOf(context)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on, color: AppTheme.primary, size: 16),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    '12 MG Road, Bengaluru',
                    style: AppTheme.captionOf(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: AppTheme.textMutedOf(context),
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
