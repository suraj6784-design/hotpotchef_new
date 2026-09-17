import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/kitchen_promise.dart';

void main() {
  test('posted weekly hours gate the kitchen in IST', () {
    final hours = {
      'mon': {'open': '11:00', 'close': '22:00'},
      'tue': {'open': '11:00', 'close': '22:00'},
      'wed': {'open': '11:00', 'close': '22:00'},
      'thu': {'open': '11:00', 'close': '22:00'},
      'fri': {'open': '11:00', 'close': '22:00'},
      'sat': {'open': '11:00', 'close': '22:00'},
      'sun': {'closed': true},
    };
    // Monday 12:00 IST = 06:30 UTC
    expect(
      kitchenHoursAccepting(hours, now: DateTime.utc(2026, 9, 14, 6, 30)),
      isTrue,
    );
    expect(
      kitchenHoursAccepting(hours, now: DateTime.utc(2026, 9, 14, 4, 0)),
      isFalse,
    );
    expect(
      kitchenHoursAccepting(hours, now: DateTime.utc(2026, 9, 13, 8, 0)),
      isFalse,
    );
    expect(kitchenHoursAccepting({}, now: DateTime.utc(2026, 9, 13, 8, 0)), isTrue);
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
