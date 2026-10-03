import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/diner_meal_catalog.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/utils/service_area.dart';

void main() {
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
}
