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
      expect(before['date'], 'Today');
      expect(before['time'], '7:30 PM to 8:30 PM');

      final insidePastStart = chefSlotDefaultSchedule(
        '7:30 PM to 8:30 PM',
        now: DateTime(2026, 9, 6, 19, 45),
      );
      expect(insidePastStart['date'], 'Today');
      expect(insidePastStart['time'], '7:30 PM to 8:30 PM');

      final after = chefSlotDefaultSchedule(
        '7:30 PM to 8:30 PM',
        now: DateTime(2026, 9, 6, 21),
      );
      expect(after['date'], 'Today');
      expect(after['time'], '7:30 PM to 8:30 PM');

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

    test('Sat/Sun kitchen windows stay preorderable on a weekday', () {
      final thursdayNight = DateTime(2026, 9, 10, 20);
      expect(isStandingWeeklyServingWindow('Sat, Sun (11:00 AM to 6:00 PM)'), isTrue);
      expect(
        isMealExpired('Sat, Sun (11:00 AM to 6:00 PM)', now: thursdayNight),
        isFalse,
      );
      expect(
        isMealAvailableForCart({
          'quantity': 5,
          'status': 'Available',
          'time_slot': 'Sat, Sun (11:00 AM to 6:00 PM)',
        }),
        isTrue,
      );
      final booked = chefSlotDefaultSchedule(
        'Sat, Sun (11:00 AM to 6:00 PM)',
        now: DateTime(2026, 9, 10, 14),
      );
      expect(booked['date'], '12 Sep 2026');
      expect(booked['time'], '11:00 AM to 12:00 PM');
      expect(chefSlotDefaultDate(booked, now: DateTime(2026, 9, 10, 14)).day, 12);
    });

    test('dated slot labels leave Active Menu after that calendar day', () {
      final now = DateTime(2026, 9, 7, 10);
      expect(parseSlotCalendarDay('Sun, 18th Aug at 9:30 AM', now: now)?.month, 8);
      expect(
        isPublishedMealExpired(
          {'time_slot': 'Sun, 18th Aug at 9:30 AM', 'status': 'Available'},
          now: now,
        ),
        isTrue,
      );
      expect(
        isChefMenuActiveMeal(
          {'time_slot': 'Today (9:00 AM to 5:00 PM)', 'status': 'Available'},
          now: DateTime(2026, 9, 7, 11),
        ),
        isTrue,
      );
      expect(
        isMealAvailableForCart(
          {'quantity': 4, 'status': 'Available', 'time_slot': 'Sun, 18th Aug at 9:30 AM'},
          now: now,
        ),
        isFalse,
      );
      expect(
        isMealExpired('Sun, 18th Aug at 9:30 AM', now: now),
        isTrue,
      );
      expect(
        isChefMenuActiveMeal({'status': 'Archived', 'time_slot': 'Today (9:00 AM to 5:00 PM)'}, now: now),
        isFalse,
      );
    });
  });

  test('diner dates stay on the chef one-time ISO day and weekday window', () {
    final now = DateTime(2026, 9, 17, 10);
    expect(parseSlotCalendarDay('2026-09-20 (12:00 PM to 2:00 PM)', now: now)?.day, 20);
    expect(
      chefSlotAllowsDate('2026-09-20 (12:00 PM to 2:00 PM)', DateTime(2026, 9, 17), now: now),
      isFalse,
    );
    expect(
      chefSlotAllowsDate('2026-09-20 (12:00 PM to 2:00 PM)', DateTime(2026, 9, 20), now: now),
      isTrue,
    );
    final booked = chefSlotDefaultSchedule(
      '2026-09-20 (12:00 PM to 2:00 PM)',
      now: now,
    );
    expect(booked['date'], '20 Sep 2026');
    expect(booked['time'], '12:00 PM to 1:00 PM');
    expect(
      chefSlotAllowsDate('Sat, Sun (11:00 AM to 6:00 PM)', DateTime(2026, 9, 17), now: now),
      isFalse,
    );
    expect(
      chefSlotAllowsDate('Sat, Sun (11:00 AM to 6:00 PM)', DateTime(2026, 9, 19), now: now),
      isTrue,
    );
    expect(
      cartLineSlotValidationError(
        selectedSlot: '12:00 PM to 1:00 PM',
        scheduledDate: DateTime(2026, 9, 17),
        chefSchedule: '2026-09-20 (12:00 PM to 2:00 PM)',
        now: now,
      ),
      contains('published slot'),
    );
  });

  test('checkout schedule uses the diner clock, not the chef window', () {
    expect(chefSlotWindowLabel('9:00 AM to 10:00 AM'), '9:00 AM to 10:00 AM');
    expect(chefSlotWindowLabel('09 Sep 2026, 09:00 AM'), '9:00 AM to 10:00 AM');
    expect(
      formatCheckoutDeliverySchedule(
        slot: '9:00 AM to 10:00 AM',
        scheduledDate: DateTime(2026, 9, 9),
        now: DateTime(2026, 9, 9, 8),
      ),
      '09 Sep 2026, 09:00 AM',
    );
    expect(feedKitchenSlotLabel('Daily (9:00 AM to 10:00 AM)'), '9:00 AM–10:00 AM');
    expect(feedKitchenSlotLabel('ASAP'), 'On your slot');
    expect(usableCustomerPhone('1234567890'), '');
    expect(usableCustomerPhone('+91 98765 43210'), '9876543210');
    expect(e164IndiaPhone('9876543210'), '+919876543210');
    expect(e164IndiaPhone('1234567890'), '');
    expect(isPlaceholderPhone('0000000000'), isTrue);
  });

  test('diner dates stay on the chef published slot', () {
    expect(parseSlotCalendarDay('2026-09-19 (12:00 PM to 2:00 PM)')?.day, 19);
    expect(
      chefSlotAllowsDate(
        '2026-09-19 (12:00 PM to 2:00 PM)',
        DateTime(2026, 9, 19),
        now: DateTime(2026, 9, 17, 10),
      ),
      isTrue,
    );
    expect(
      chefSlotAllowsDate(
        '2026-09-19 (12:00 PM to 2:00 PM)',
        DateTime(2026, 9, 18),
        now: DateTime(2026, 9, 17, 10),
      ),
      isFalse,
    );
    expect(
      chefSlotAllowsDate(
        'Sat, Sun (11:00 AM to 6:00 PM)',
        DateTime(2026, 9, 11),
        now: DateTime(2026, 9, 10, 14),
      ),
      isFalse,
    );
    expect(
      chefSlotAllowsDate(
        'Sat, Sun (11:00 AM to 6:00 PM)',
        DateTime(2026, 9, 12),
        now: DateTime(2026, 9, 10, 14),
      ),
      isTrue,
    );
    final oneTime = chefSlotDefaultSchedule(
      '2026-09-19 (12:00 PM to 2:00 PM)',
      now: DateTime(2026, 9, 17, 10),
    );
    expect(chefSlotDefaultDate(oneTime, now: DateTime(2026, 9, 17, 10)).day, 19);
    expect(oneTime['time'], '12:00 PM to 1:00 PM');
    expect(
      cartLineSlotValidationError(
        selectedSlot: '12:00 PM to 1:00 PM',
        scheduledDate: DateTime(2026, 9, 18),
        chefSchedule: '2026-09-19 (12:00 PM to 2:00 PM)',
        now: DateTime(2026, 9, 17, 10),
      ),
      contains('published slot'),
    );
  });
}
