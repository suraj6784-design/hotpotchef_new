import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/services/shared_cart_service.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/widgets/cart_slot_issue_notice.dart';

void main() {
  final pastDay = DateTime(2026, 10, 4);
  final today = DateTime(2026, 10, 5, 15);
  const deadSlot = '4:00 AM to 5:00 AM';

  group('shared room join', () {
    test('refuses a room whose shared date and slot already passed', () {
      final reason = sharedRoomJoinRefusal(
        timeSlot: deadSlot,
        selectedDate: pastDay,
        now: today,
      );
      expect(reason, kPastGroupRoomJoinMessage);
      expect(reason, contains('That time slot has passed'));
    });

    test('refuses a same-day slot once its start has passed', () {
      expect(
        sharedRoomJoinRefusal(
          timeSlot: deadSlot,
          selectedDate: DateTime(2026, 10, 5),
          now: DateTime(2026, 10, 5, 4, 5),
        ),
        kPastGroupRoomJoinMessage,
      );
    });

    test('still accepts a later slot the host can move the room to', () {
      expect(
        sharedRoomJoinRefusal(
          timeSlot: '6:00 PM to 7:00 PM',
          selectedDate: DateTime(2026, 10, 6),
          now: today,
        ),
        isNull,
      );
      expect(
        sharedRoomJoinRefusal(
          timeSlot: '4:00 PM to 5:00 PM',
          selectedDate: DateTime(2026, 10, 5),
          now: DateTime(2026, 10, 5, 9),
        ),
        isNull,
      );
    });

    test('refuses a past calendar day even when the slot text is blank', () {
      expect(
        sharedRoomJoinRefusal(timeSlot: '', selectedDate: pastDay, now: today),
        kPastGroupRoomJoinMessage,
      );
    });

    test('does not grow a dead room with another plate', () {
      expect(
        sharedRoomBlocksNewPlates(
          inGroup: true,
          timeSlot: deadSlot,
          selectedDate: pastDay,
          now: today,
        ),
        isTrue,
      );
      expect(
        sharedRoomBlocksNewPlates(
          inGroup: false,
          timeSlot: deadSlot,
          selectedDate: pastDay,
          now: today,
        ),
        isFalse,
      );
      expect(
        sharedRoomBlocksNewPlates(
          inGroup: true,
          timeSlot: '6:00 PM to 7:00 PM',
          selectedDate: DateTime(2026, 10, 6),
          now: today,
        ),
        isFalse,
      );
    });

    test('does not invent a refusal when the room has no clock', () {
      expect(
        sharedRoomJoinRefusal(timeSlot: null, selectedDate: null, now: today),
        isNull,
      );
    });

    test('parses the stored room date the same way join does', () {
      expect(
        sharedRoomJoinRefusal(
          timeSlot: deadSlot,
          selectedDate: parseFlexibleDate('2026-10-04T04:00:00.000Z'),
          now: today,
        ),
        kPastGroupRoomJoinMessage,
      );
    });
  });

  group('group cart warning', () {
    test('surfaces the same past-slot warning solo plates already use', () {
      final issue = groupCartDisplayedSlotIssue(
        inGroup: true,
        roomTimeSlot: deadSlot,
        roomDate: pastDay,
        selectedSlot: '12:00 PM to 1:00 PM',
        scheduledDate: DateTime(2026, 10, 6),
        chefSchedule: '9:00 AM to 5:00 PM',
        now: today,
      );
      expect(issue, kPastSlotCartMessage);
      expect(
        cartLineSlotValidationError(
          selectedSlot: deadSlot,
          scheduledDate: pastDay,
          chefSchedule: '4:00 AM to 10:00 AM',
          now: today,
        ),
        issue,
      );
    });

    test('stays quiet for a future room so the host can still edit it', () {
      expect(
        groupCartDisplayedSlotIssue(
          inGroup: true,
          roomTimeSlot: '6:00 PM to 7:00 PM',
          roomDate: DateTime(2026, 10, 6),
          selectedSlot: '6:00 PM to 7:00 PM',
          scheduledDate: DateTime(2026, 10, 6),
          chefSchedule: '9:00 AM to 5:00 PM',
          now: today,
        ),
        isNull,
      );
    });

    test('solo carts keep chef-window and past-slot checks', () {
      expect(
        groupCartDisplayedSlotIssue(
          inGroup: false,
          selectedSlot: '6:00 PM to 7:00 PM',
          scheduledDate: DateTime(2026, 10, 6),
          chefSchedule: '9:00 AM to 5:00 PM',
          now: today,
        ),
        'Choose a time inside the chef\'s published serving window.',
      );
      expect(
        groupCartDisplayedSlotIssue(
          inGroup: false,
          selectedSlot: deadSlot,
          scheduledDate: pastDay,
          chefSchedule: '4:00 AM to 10:00 AM',
          now: today,
        ),
        kPastSlotCartMessage,
      );
      expect(
        groupCartDisplayedSlotIssue(
          inGroup: false,
          selectedSlot: '12:00 PM to 1:00 PM',
          scheduledDate: DateTime(2026, 10, 6),
          chefSchedule: '9:00 AM to 5:00 PM',
          now: today,
        ),
        isNull,
      );
    });
  });

  test('a host can still write a future slot onto the room', () {
    final patch = authorizeSharedRoomPatch(
      userId: 'host',
      hostId: 'host',
      patch: const SharedRoomPatch(
        timeSlot: '6:00 PM to 7:00 PM',
        selectedDate: null,
      ),
    );
    expect(patch, isNotNull);
    final moved = SharedRoomPatch(
      timeSlot: patch!.timeSlot,
      selectedDate: DateTime(2026, 10, 6),
    );
    expect(
      sharedRoomJoinRefusal(
        timeSlot: moved.timeSlot,
        selectedDate: moved.selectedDate,
        now: today,
      ),
      isNull,
    );
    expect(
      groupCartDisplayedSlotIssue(
        inGroup: true,
        roomTimeSlot: moved.timeSlot,
        roomDate: moved.selectedDate,
        selectedSlot: deadSlot,
        scheduledDate: pastDay,
        chefSchedule: '4:00 AM to 10:00 AM',
        now: today,
      ),
      isNull,
    );
  });

  testWidgets('group cart notice shows the past-slot warning', (tester) async {
    final message = groupCartDisplayedSlotIssue(
      inGroup: true,
      roomTimeSlot: deadSlot,
      roomDate: pastDay,
      selectedSlot: deadSlot,
      scheduledDate: pastDay,
      chefSchedule: '4:00 AM to 10:00 AM',
      now: today,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CartSlotIssueNotice(message: message)),
      ),
    );

    expect(find.text(kPastSlotCartMessage), findsOneWidget);
  });

  testWidgets('a bookable solo plate does not show the past-slot warning', (tester) async {
    final message = groupCartDisplayedSlotIssue(
      inGroup: false,
      selectedSlot: '12:00 PM to 1:00 PM',
      scheduledDate: DateTime(2026, 10, 6),
      chefSchedule: '9:00 AM to 5:00 PM',
      now: today,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CartSlotIssueNotice(message: message)),
      ),
    );

    expect(find.textContaining('That time slot has passed'), findsNothing);
    expect(find.byType(CartSlotIssueNotice), findsOneWidget);
  });
}
