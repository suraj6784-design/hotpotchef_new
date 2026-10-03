import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/delivery_pin.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

/// Breakfast order 4D6B2765 dropoff: 9 Thergaon.
const _dropLat = 18.6147;
const _dropLng = 73.7668;

/// Point due north of the Thergaon pin, measured with the same haversine
/// the arrival gate uses.
double _northOfDropoff(double meters) {
  var lat = _dropLat + meters / 111194.9;
  for (var i = 0; i < 4; i++) {
    final actual = haversineKm(lat, _dropLng, _dropLat, _dropLng) * 1000;
    if (actual == 0) break;
    lat = _dropLat + (lat - _dropLat) * (meters / actual);
  }
  return lat;
}

void main() {
  test('within 80 meters Mark Delivered may ask for the PIN', () {
    final atDoor = markDeliveredBlockReason(
      driverLat: _dropLat,
      driverLng: _dropLng,
      dropoffLat: _dropLat,
      dropoffLng: _dropLng,
    );
    expect(atDoor, isNull);

    final nearLat = _northOfDropoff(50);
    expect(
      haversineKm(nearLat, _dropLng, _dropLat, _dropLng) * 1000,
      lessThan(kDropoffArrivalRadiusMeters),
    );
    expect(
      markDeliveredBlockReason(
        driverLat: nearLat,
        driverLng: _dropLng,
        dropoffLat: _dropLat,
        dropoffLng: _dropLng,
      ),
      isNull,
    );

    final edgeLat = _northOfDropoff(kDropoffArrivalRadiusMeters);
    final edgeMeters = haversineKm(edgeLat, _dropLng, _dropLat, _dropLng) * 1000;
    expect(edgeMeters, lessThanOrEqualTo(kDropoffArrivalRadiusMeters));
    expect(edgeMeters, greaterThan(kDropoffArrivalRadiusMeters - 1));
    expect(
      markDeliveredBlockReason(
        driverLat: edgeLat,
        driverLng: _dropLng,
        dropoffLat: _dropLat,
        dropoffLng: _dropLng,
      ),
      isNull,
    );
    expect(
      driverHasReachedDropoff(
        driverLat: edgeLat,
        driverLng: _dropLng,
        dropoffLat: _dropLat,
        dropoffLng: _dropLng,
      ),
      isTrue,
    );
  });

  test('farther than 80 meters blocks the PIN dialog and names the dropoff', () {
    final farLat = _northOfDropoff(81);
    final farMeters = haversineKm(farLat, _dropLng, _dropLat, _dropLng) * 1000;
    expect(farMeters, greaterThan(kDropoffArrivalRadiusMeters));
    expect(farMeters, lessThan(kDropoffArrivalRadiusMeters + 2));

    final blocked = markDeliveredBlockReason(
      driverLat: farLat,
      driverLng: _dropLng,
      dropoffLat: _dropLat,
      dropoffLng: _dropLng,
    );
    expect(blocked, isNotNull);
    expect(blocked, markDeliveredTooFarMessage());
    expect(blocked!.toLowerCase(), contains('near the dropoff'));
    expect(blocked, contains('${kDropoffArrivalRadiusMeters.round()}'));
    expect(
      driverHasReachedDropoff(
        driverLat: farLat,
        driverLng: _dropLng,
        dropoffLat: _dropLat,
        dropoffLng: _dropLng,
      ),
      isFalse,
    );

    // About 1km north of Thergaon — still on the way, not at the door.
    final wayOff = _northOfDropoff(1000);
    expect(
      haversineKm(wayOff, _dropLng, _dropLat, _dropLng) * 1000,
      greaterThan(kDropoffArrivalRadiusMeters),
    );
    expect(
      markDeliveredBlockReason(
        driverLat: wayOff,
        driverLng: _dropLng,
        dropoffLat: _dropLat,
        dropoffLng: _dropLng,
      ),
      markDeliveredTooFarMessage(),
    );
  });

  test('a missing driver fix cannot open the PIN dialog', () {
    final blocked = markDeliveredBlockReason(
      driverLat: null,
      driverLng: null,
      dropoffLat: _dropLat,
      dropoffLng: _dropLng,
    );
    expect(blocked, markDeliveredTooFarMessage());
    expect(
      markDeliveredBlockReason(
        driverLat: _dropLat,
        driverLng: _dropLng,
        dropoffLat: null,
        dropoffLng: null,
      ),
      markDeliveredTooFarMessage(),
    );
  });
}
