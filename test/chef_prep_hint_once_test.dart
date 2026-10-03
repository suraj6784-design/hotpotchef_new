import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/widgets/order_slot_banner.dart';

/// Confirmed Breakfast order 4D6B2765, 18 hr 33 min before 04 Oct 2026 08:00.
void main() {
  final order = <String, dynamic>{
    'status': 'Confirmed',
    'created_at': DateTime(2026, 10, 3, 6, 57).toIso8601String(),
    'items': jsonEncode([
      {
        'title': 'Breakfast',
        'quantity': 1,
        'exact_time': '8:00 AM to 9:00 AM',
        'time_slot': '8:00 AM to 9:00 AM',
        'selected_date': '2026-10-04',
        'selected_year': 2026,
      },
    ]),
  };

  final start = orderSlotStart(order)!;
  final now = start.subtract(const Duration(hours: 18, minutes: 33));

  const sentence = 'Opens in 14 hr 33 min (4 hours before requested time)';

  test('the prepare sentence is the 4-hour gap before 08:00', () {
    expect(kChefPrepEarliestMinutes, 240);
    expect(canChefStartPreparing(order, now: now), isFalse);
    expect(chefPrepGateHint(order, now: now), sentence);
    expect(
      canChefStartPreparing(order, now: start.subtract(const Duration(hours: 4))),
      isTrue,
    );
  });

  testWidgets('confirmed In Progress card shows the prepare sentence once', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: chefKitchenOrderTiming(
              order: order,
              isPending: false,
              isPreparing: false,
              now: now,
            ),
          ),
        ),
      ),
    );

    expect(find.text(sentence), findsOneWidget);
    expect(find.text('Requested 04 Oct 2026, 08:00 AM'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending and preparing cards do not show the prepare sentence', (tester) async {
    for (final pending in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: chefKitchenOrderTiming(
                order: order,
                isPending: pending,
                isPreparing: !pending,
                now: now,
              ),
            ),
          ),
        ),
      );
      expect(find.text(sentence), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
