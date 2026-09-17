import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/utils/kitchen_promise.dart';

void main() {
  test('offline kitchens do not take orders; hours are ignored', () {
    expect(isChefKitchenAcceptingOrders({'is_open': true}), isTrue);
    expect(isChefKitchenAcceptingOrders({'is_open': false}), isFalse);
    expect(
      isChefKitchenAcceptingOrders({
        'is_open': true,
        'weekly_hours': {'sun': {'closed': true}},
      }),
      isTrue,
    );
  });

  test('prep plus travel become the diner ETA', () {
    expect(promisedEtaMinutes(distanceKm: 0, prepMinutes: 30), 50);
    expect(promisedEtaMinutes(distanceKm: 5, prepMinutes: 30), 45);
  });

  test('late copy promises 25 coins after a 15 minute grace', () {
    final now = DateTime(2026, 9, 17, 13, 0);
    final onTime = {
      'promised_at': DateTime(2026, 9, 17, 13, 10).toIso8601String(),
      'status': 'On the way',
    };
    final late = {
      'promised_at': DateTime(2026, 9, 17, 12, 40).toIso8601String(),
      'status': 'On the way',
    };
    expect(orderQualifiesLateCompensation(onTime, now: now), isFalse);
    expect(dinerLateOrderCopy(onTime, now: now), '');
    expect(orderQualifiesLateCompensation(late, now: now), isTrue);
    expect(dinerLateOrderCopy(late, now: now), contains('25 HotPot Coins'));
  });
}
