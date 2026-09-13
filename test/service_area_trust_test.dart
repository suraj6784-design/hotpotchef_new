import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/utils/service_area.dart';

void main() {
  group('service area', () {
    test('Pune metro pins and bbox are live', () {
      expect(isInLaunchServiceArea(pincode: '411004'), isTrue);
      expect(isInLaunchServiceArea(pincode: '412105'), isTrue);
      expect(isInLaunchServiceArea(lat: 18.52, lng: 73.85), isTrue);
      expect(serviceCityForPin('411038')?.id, 'pune');
    });

    test('outside pins are not serviceable when known', () {
      expect(isInLaunchServiceArea(pincode: '560001'), isFalse);
      expect(isInLaunchServiceArea(lat: 19.07, lng: 72.87), isFalse);
      expect(
        serviceAreaCheckoutWarning(pincode: '560001'),
        contains('Pune'),
      );
    });

    test('unknown pin without coordinates is not blocked', () {
      expect(isInLaunchServiceArea(), isTrue);
      expect(serviceAreaCheckoutWarning(), isNull);
    });

    test('pageCatalog slices later plates for Home load-more', () {
      final items = List.generate(200, (i) => i);
      expect(pageCatalog(items, page: 0, pageSize: 80), hasLength(80));
      expect(pageCatalog(items, page: 1, pageSize: 80).first, 80);
      expect(pageCatalog(items, page: 3, pageSize: 80), isEmpty);
    });
  });

  group('kitchen trust', () {
    test('verified licence plus reviews scores high; expired is not diner-verified', () {
      expect(dinerFssaiIsVerified('verified'), isTrue);
      expect(
        dinerFssaiIsVerified('verified', validUntil: DateTime(2025, 1, 1), now: DateTime(2026, 9, 14)),
        isFalse,
      );
      expect(
        dinerFssaiTrustLabel(
          fssaiNumber: '11234567890123',
          verificationStatus: 'verified',
          validUntil: DateTime(2025, 6, 1),
          now: DateTime(2026, 9, 14),
        ),
        contains('expired'),
      );
      final score = kitchenTrustScore(
        verificationStatus: 'verified',
        validUntil: DateTime(2027, 1, 1),
        ratings: const ChefRatingSummary(average: 4.8, count: 12),
        now: DateTime(2026, 9, 14),
      );
      expect(score, greaterThanOrEqualTo(70));
      expect(kitchenTrustLabel(score), contains('/100'));
    });
  });
}
