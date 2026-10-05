import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/diner_meal_catalog.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/utils/pinned_address.dart';
import 'package:hotpotchef_new/utils/service_area.dart';

void main() {
  test('diner home greeting follows the time of day', () {
    expect(dinerHomeGreeting(DateTime(2026, 10, 5, 8)), 'Good morning');
    expect(dinerHomeGreeting(DateTime(2026, 10, 5, 14)), 'Good afternoon');
    expect(dinerHomeGreeting(DateTime(2026, 10, 5, 19)), 'Good evening');
  });

  test('diner catalog select skips payout, FSSAI, and order columns', () {
    final columns = dinerMealCatalogColumnSet();
    expect(columns, containsAll(['id', 'title', 'status', 'pickup_lat', 'pickup_lng', 'hosting_address', 'prep_minutes']));
    for (final denied in kDinerMealCatalogPrivateColumns) {
      expect(columns, isNot(contains(denied)), reason: denied);
    }
  });

  test('a failed catalog with no payload is a connection failure', () {
    final phase = dinerHomeFeedPhase(
      loading: false,
      error: Exception('permission denied'),
      hasPayload: false,
    );
    expect(phase, DinerHomeFeedPhase.failed);
    expect(dinerHomeFeedIsConnectionFailure(phase), isTrue);
  });

  test('a successful empty catalog is not a connection failure', () {
    final phase = dinerHomeFeedPhase(
      loading: false,
      error: null,
      hasPayload: true,
    );
    expect(phase, DinerHomeFeedPhase.ready);
    expect(dinerHomeFeedIsConnectionFailure(phase), isFalse);
    final copy = feedEmptyCopy(
      signedIn: false,
      favoritesOnly: false,
      hasFavorites: false,
      hasSearch: false,
      hasDeliveryPin: true,
    );
    expect(copy.title, 'No meals found');
    expect(copy.message, contains('this pin'));
  });

  test('a payload is kept when a later refresh fails', () {
    final phase = dinerHomeFeedPhase(
      loading: false,
      error: Exception('timed out'),
      hasPayload: true,
    );
    expect(dinerHomeFeedIsConnectionFailure(phase), isFalse);
  });

  test('outside the launch cities uses the empty-area copy', () {
    final phase = dinerHomeFeedPhase(loading: false, error: null, hasPayload: true);
    expect(dinerHomeFeedIsConnectionFailure(phase), isFalse);
    final copy = feedEmptyCopy(
      signedIn: true,
      favoritesOnly: false,
      hasFavorites: false,
      hasSearch: false,
      hasDeliveryPin: true,
      outOfServiceArea: true,
    );
    expect(copy.title, contains('Pune'));
    expect(copy.message, contains('Change your pin'));
  });

  test('the Wakad pin is inside the live kitchen radius', () {
    const wakadLat = 18.5959;
    const wakadLng = 73.7714;
    const kitchenLat = 18.6267236790653;
    const kitchenLng = 73.7782157957554;
    final roadKm = haversineKm(kitchenLat, kitchenLng, wakadLat, wakadLng) * 1.3;
    expect(roadKm, lessThan(15));
    expect(
      isInLaunchServiceArea(pincode: '411057', lat: wakadLat, lng: wakadLng),
      isTrue,
    );
    expect(
      mealInDeliveryRadius(
        {'pickup_lat': kitchenLat, 'pickup_lng': kitchenLng},
        destinationLat: wakadLat,
        destinationLng: wakadLng,
      ),
      isTrue,
    );
  });

  test('12:51 AM Sunday does not tell the diner the pin has no kitchens', () {
    final now = DateTime(2026, 10, 4, 0, 51);
    expect(now.weekday, DateTime.sunday);
    final chef = <String, dynamic>{'is_open': true, 'is_live': false};
    final profiles = <String, Map<String, dynamic>>{'newchef16': chef};
    Map<String, dynamic> plate(String title, String slot) => {
          'title': title,
          'is_veg': true,
          'status': 'Available',
          'availability_mode': 'live',
          'chef_id': 'newchef16',
          'time_slot': slot,
        };
    final meals = [
      plate('Breakfast', 'Daily (8:00 AM to 11:30 AM)'),
      plate('Veg Biryani', 'Daily (9:00 AM to 11:00 PM)'),
      plate('Veg Jumbo Thali', 'Sat, Sun (9:00 AM to 11:00 PM)'),
      plate('Gulab Jamun', 'Today at 01:00 AM'),
      plate('SweetDish', 'Today at 01:00 AM'),
    ];

    for (final meal in meals) {
      expect(
        mealMatchesHomeMode(meal, mode: 'live', now: now, chefProfile: chef),
        isFalse,
        reason: '${meal['title']} is outside the live window',
      );
    }
    for (final title in ['Breakfast', 'Veg Biryani', 'Veg Jumbo Thali']) {
      final meal = meals.firstWhere((row) => row['title'] == title);
      expect(mealMatchesHomeMode(meal, mode: 'preorder', now: now, chefProfile: chef), isTrue, reason: title);
    }

    final mode = dinerColdStartHomeMode(
      meals: meals,
      dinerChoseMode: false,
      requestedMode: 'live',
      diet: 'Veg',
      chefProfiles: profiles,
      now: now,
    );
    expect(mode, 'preorder');
    final shown = dinerHomeMealsForMode(
      meals,
      mode: mode,
      diet: 'Veg',
      chefProfiles: profiles,
      now: now,
    ).map((meal) => meal['title']).toList();
    expect(
      shown,
      dinerHomeMealsForMode(
        meals,
        mode: 'preorder',
        diet: 'Veg',
        chefProfiles: profiles,
        now: now,
      ).map((meal) => meal['title']).toList(),
    );
    expect(shown, containsAll(['Breakfast', 'Veg Biryani', 'Veg Jumbo Thali']));

    final quiet = feedEmptyCopy(
      signedIn: true,
      favoritesOnly: false,
      hasFavorites: false,
      hasSearch: false,
      diet: 'Veg',
      hasDeliveryPin: true,
      homeMode: 'live',
      nothingLive: true,
      hasPreorderMeals: true,
    );
    final blob = '${quiet.title} ${quiet.message}'.toLowerCase();
    expect(quiet.title, 'Nobody is cooking right now');
    expect(blob, isNot(contains('no meals')));
    expect(blob, isNot(contains('no veg')));
    expect(blob, isNot(contains('no kitchens')));
    expect(blob, isNot(contains('this pin')));
    expect(quiet.offerPreorder, isTrue);
    expect(quiet.message, contains('Live Order'));
    expect(quiet.message, contains('Pre-order'));
    expect(
      dinerColdStartHomeMode(
        meals: meals,
        dinerChoseMode: true,
        requestedMode: 'live',
        diet: 'Veg',
        chefProfiles: profiles,
        now: now,
      ),
      'live',
    );

    final evening = DateTime(2026, 10, 4, 19);
    expect(dinerPinHasAcceptingMeal(meals, chefProfiles: profiles, now: evening), isTrue);
    expect(
      dinerColdStartHomeMode(
        meals: meals,
        dinerChoseMode: false,
        diet: 'Veg',
        chefProfiles: profiles,
        now: evening,
      ),
      'live',
    );
    final liveTitles = dinerHomeMealsForMode(
      meals,
      mode: 'live',
      diet: 'Veg',
      chefProfiles: profiles,
      now: evening,
    ).map((meal) => meal['title']).toList();
    expect(liveTitles, containsAll(['Veg Biryani', 'Veg Jumbo Thali']));
    expect(liveTitles, isNot(contains('Breakfast')));
  });

  test('a kitchen pin still counts when the address column was not selected', () {
    expect(
      mealFailsCurrentCatalogRequirements({
        'title': 'Breakfast',
        'price': 90,
        'status': 'Available',
        'service_type': 'Delivery',
        'time_slot': 'Daily (8:00 AM to 11:30 AM)',
        'pickup_lat': 18.6267,
        'pickup_lng': 73.7782,
      }),
      isFalse,
    );
    expect(
      mealFailsCurrentCatalogRequirements({
        'title': 'Breakfast',
        'price': 90,
        'status': 'Available',
        'service_type': 'Delivery',
        'time_slot': 'Daily (8:00 AM to 11:30 AM)',
        'pickup_lat': 18.6267,
        'pickup_lng': 73.7782,
        'hosting_address': '',
      }),
      isTrue,
    );
  });

  test('guest pin follows device location', () {
    expect(guestColdStartShouldRequestLocation(signedIn: false), isTrue);
    expect(guestColdStartShouldRequestLocation(signedIn: true), isFalse);

    const deviceLat = 18.5912;
    const deviceLng = 73.7389;
    final pin = guestDeviceDeliveryPin(
      permissionGranted: true,
      latitude: deviceLat,
      longitude: deviceLng,
      street: 'Baner',
      city: 'Pune',
      state: 'Maharashtra',
      pincode: '411045',
    );
    expect(pin, isNotNull);
    expect(pin!['is_device_location'], isTrue);
    expect(pin['is_launch_city'], isNot(true));
    expect(pin['latitude'], deviceLat);
    expect(pin['longitude'], deviceLng);
    expect(pin['latitude'], isNot(launchCityDefaultPin()['latitude']));
    expect(pin['longitude'], isNot(launchCityDefaultPin()['longitude']));

    final chip = guestDeliveryChipLabel(pin);
    expect(chip, 'Baner, Pune - 411045');
    expect(chip, isNot(kGuestLocationUnsetLabel));
    expect(chip, isNot('Select location'));

    expect(
      kitchenServesDinerPin(
        kitchenLat: 18.60,
        kitchenLng: 73.74,
        dinerLat: deviceLat,
        dinerLng: deviceLng,
        dinerPincode: pin['pincode']?.toString(),
        kitchenPincode: '411045',
      ),
      isTrue,
    );
    expect(
      kitchenServesDinerPin(
        kitchenLat: 19.07,
        kitchenLng: 72.87,
        dinerLat: deviceLat,
        dinerLng: deviceLng,
        dinerPincode: pin['pincode']?.toString(),
        kitchenPincode: '400001',
      ),
      isFalse,
    );

    expect(
      guestDeviceDeliveryPin(
        permissionGranted: false,
        latitude: launchCityDefaultPin()['latitude'] as double,
        longitude: launchCityDefaultPin()['longitude'] as double,
        city: 'Pune',
        pincode: '411001',
      ),
      isNull,
    );
    expect(
      guestDeviceDeliveryPin(permissionGranted: true, latitude: null, longitude: null),
      isNull,
    );
    expect(
      guestDeviceDeliveryPin(permissionGranted: true, latitude: 0, longitude: 0),
      isNull,
    );
    expect(guestDeliveryChipLabel(null), kGuestLocationUnsetLabel);
  });
}
