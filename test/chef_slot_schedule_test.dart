import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('chefHourlySubSlots', () {
    test('splits a chef window into hourly bookable ranges', () {
      expect(
        chefHourlySubSlots('Today (9:00 AM to 12:00 PM)'),
        [
          '9:00 AM to 10:00 AM',
          '10:00 AM to 11:00 AM',
          '11:00 AM to 12:00 PM',
        ],
      );
    });
  });

  group('chefSlotDefaultSchedule', () {
    test('never defaults to a past clock inside the chef window', () {
      final before = chefSlotDefaultSchedule(
        '7:30 PM to 8:30 PM',
        now: DateTime(2026, 9, 6, 12),
      );
      expect(before, {'date': 'Today', 'time': '7:30 PM to 8:30 PM'});

      final insidePastStart = chefSlotDefaultSchedule(
        '7:30 PM to 8:30 PM',
        now: DateTime(2026, 9, 6, 19, 45),
      );
      expect(insidePastStart, {'date': 'Tomorrow', 'time': '7:30 PM to 8:30 PM'});

      final after = chefSlotDefaultSchedule(
        '7:30 PM to 8:30 PM',
        now: DateTime(2026, 9, 6, 21),
      );
      expect(after, {'date': 'Tomorrow', 'time': '7:30 PM to 8:30 PM'});

      final lateMorning = chefSlotDefaultSchedule(
        'Today (9:00 AM to 5:00 PM)',
        now: DateTime(2026, 9, 6, 11, 1),
      );
      expect(lateMorning['date'], 'Today');
      expect(lateMorning['time'], '12:00 PM to 1:00 PM');

      expect(preferredChefSlotClock('1:00 PM to 2:00 PM'), '1:00 PM');
      expect(preferredChefSlotClock('ASAP'), isNull);
    });
  });

  group('cart slot guards', () {
    test('rejects passed slots and slots outside the chef window', () {
      final day = DateTime(2026, 9, 6);
      expect(
        isCartSlotPassed('9:00 AM to 10:00 AM', day, now: DateTime(2026, 9, 6, 11, 1)),
        isTrue,
      );
      expect(
        isCartSlotPassed('12:00 PM to 1:00 PM', day, now: DateTime(2026, 9, 6, 11, 1)),
        isFalse,
      );
      expect(
        isCartSlotWithinChefWindow('12:00 PM to 1:00 PM', '9:00 AM to 5:00 PM'),
        isTrue,
      );
      expect(
        isCartSlotWithinChefWindow('6:00 PM to 7:00 PM', '9:00 AM to 5:00 PM'),
        isFalse,
      );
      expect(
        cartLineSlotValidationError(
          selectedSlot: '9:00 AM',
          scheduledDate: day,
          chefSchedule: '9:00 AM to 5:00 PM',
          now: DateTime(2026, 9, 6, 11, 1),
        ),
        contains('passed'),
      );
    });

    test('isMealExpired uses the window end, not start+3h', () {
      expect(
        isMealExpired(
          'Today (9:00 AM to 5:00 PM)',
          now: DateTime(2026, 9, 6, 11, 1),
        ),
        isFalse,
      );
      expect(
        isMealExpired(
          'Today (9:00 AM to 5:00 PM)',
          now: DateTime(2026, 9, 6, 17, 0),
        ),
        isTrue,
      );
    });
  });
}
