import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/delivery_pin.dart';

void main() {
  const dropLat = 18.5204;
  const dropLng = 73.8567;

  test(
    'confirmed Breakfast hides the PIN until the partner reaches the dropoff',
    () {
      final confirmed = {
        'id': '4d6b2765-c401-4f1a-ae33-8c96c8c4f476',
        'status': 'Confirmed',
        'delivery_otp': '8784',
      };

      expect(dinerVisibleDeliveryPin(confirmed), isEmpty);
      expect(
        dinerVisibleDeliveryPin({...confirmed, 'status': 'Out for Delivery'}),
        isEmpty,
      );
      expect(
        dinerVisibleDeliveryPin({
          ...confirmed,
          'status': 'Out for Delivery',
          'driver_arrived_at': '2026-10-04T02:30:00Z',
        }),
        '8784',
      );
      expect(
        dinerVisibleDeliveryPin({
          ...confirmed,
          'status': 'Delivered',
          'driver_arrived_at': '2026-10-04T02:30:00Z',
        }),
        isEmpty,
      );
    },
  );

  test('dropoff arrival is an 80 meter gate around the diner pin', () {
    expect(
      driverHasReachedDropoff(
        driverLat: dropLat,
        driverLng: dropLng,
        dropoffLat: dropLat,
        dropoffLng: dropLng,
      ),
      isTrue,
    );
    // About 50m north.
    expect(
      driverHasReachedDropoff(
        driverLat: dropLat + 0.00045,
        driverLng: dropLng,
        dropoffLat: dropLat,
        dropoffLng: dropLng,
      ),
      isTrue,
    );
    // About 1km north — still on the way, not at the door.
    expect(
      driverHasReachedDropoff(
        driverLat: dropLat + 0.009,
        driverLng: dropLng,
        dropoffLat: dropLat,
        dropoffLng: dropLng,
      ),
      isFalse,
    );
    expect(
      driverHasReachedDropoff(
        driverLat: dropLat,
        driverLng: dropLng,
        dropoffLat: null,
        dropoffLng: dropLng,
      ),
      isFalse,
    );
  });
}
