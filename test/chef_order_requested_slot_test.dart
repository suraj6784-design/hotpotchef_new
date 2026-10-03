import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/chef_order_realtime.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/widgets/order_slot_banner.dart';

/// Order 4D6B2765: Breakfast, diner slot 04 Oct 2026 08:00 AM.
/// Accept updates status only. `items` is toasted text, so the realtime
/// UPDATE record omits it and the old stream replaced the whole row.
void main() {
  const orderId = '4d6b2765-c401-4f1a-ae33-8c96c8c4f476';
  final items = jsonEncode([
    {
      'title': 'Breakfast',
      'quantity': 1,
      'exact_time': '8:00 AM to 9:00 AM',
      'time_slot': '8:00 AM to 9:00 AM',
      'chef_schedule': 'Daily (8:00 AM to 11:30 AM)',
      'selected_date': '2026-10-04',
      'selected_year': 2026,
      'rawMealDetails': {
        'time_slot': 'Daily (8:00 AM to 11:30 AM)',
        'exact_time': '8:00 AM to 9:00 AM',
      },
    },
  ]);

  final pending = <String, dynamic>{
    'id': orderId,
    'status': 'Pending Chef Approval',
    'created_at': '2026-10-03T06:57:27.791921Z',
    'promised_at': '2026-10-04T02:30:00Z',
    'items': items,
  };

  final acceptedWithoutItems = <String, dynamic>{
    'id': orderId,
    'status': 'Confirmed',
    'created_at': pending['created_at'],
    'promised_at': pending['promised_at'],
    'items': null,
  };

  test(
    'stored items show the diner slot; a status payload that drops items says ASAP',
    () {
      expect(orderSlotBannerTitle(pending), 'Requested 04 Oct 2026, 08:00 AM');
      expect(formatDeliverySlotLabel(acceptedWithoutItems), 'ASAP');
      expect(orderSlotBannerTitle(acceptedWithoutItems), 'Requested ASAP');
      expect(kChefPrepEarliestMinutes, 240);
    },
  );

  test('accept keeps the diner slot when realtime drops toasted items', () {
    final rows = applyChefOrderRealtimeEvent(
      [pending],
      event: 'update',
      record: acceptedWithoutItems,
    );
    expect(rows.single['status'], 'Confirmed');
    expect(rows.single['items'], items);
    expect(
      orderSlotBannerTitle(rows.single),
      'Requested 04 Oct 2026, 08:00 AM',
    );

    final start = orderSlotStart(rows.single);
    expect(start, isNotNull);
    expect(
      canChefStartPreparing(
        rows.single,
        now: start!.subtract(const Duration(hours: 5)),
      ),
      isFalse,
    );
    expect(
      canChefStartPreparing(
        rows.single,
        now: start.subtract(const Duration(hours: 4)),
      ),
      isTrue,
    );
  });

  test('a missing items key is the same drop as a null items column', () {
    final incoming = Map<String, dynamic>.from(acceptedWithoutItems)
      ..remove('items');
    final rows = applyChefOrderRealtimeEvent(
      [pending],
      event: 'update',
      record: incoming,
    );
    expect(
      orderSlotBannerTitle(rows.single),
      'Requested 04 Oct 2026, 08:00 AM',
    );
  });

  test('a real items rewrite still replaces the slot', () {
    final next = jsonEncode([
      {
        'title': 'Breakfast',
        'exact_time': '9:00 AM to 10:00 AM',
        'time_slot': '9:00 AM to 10:00 AM',
        'selected_date': '2026-10-04',
        'selected_year': 2026,
      },
    ]);
    final rows = applyChefOrderRealtimeEvent(
      [pending],
      event: 'update',
      record: {'id': orderId, 'status': 'Confirmed', 'items': next},
    );
    expect(
      orderSlotBannerTitle(rows.single),
      'Requested 04 Oct 2026, 09:00 AM',
    );
  });

  test('non-toasted nulls still clear', () {
    final rows = applyChefOrderRealtimeEvent(
      [
        {...pending, 'driver_id': 'driver-1'},
      ],
      event: 'update',
      record: {'id': orderId, 'driver_id': null, 'status': 'Confirmed'},
    );
    expect(rows.single['driver_id'], isNull);
    expect(rows.single.containsKey('items'), isTrue);
    expect(
      orderSlotBannerTitle(rows.single),
      'Requested 04 Oct 2026, 08:00 AM',
    );
  });

  testWidgets('In Progress card shows the diner slot after accept', (
    tester,
  ) async {
    final rows = applyChefOrderRealtimeEvent(
      [pending],
      event: 'update',
      record: acceptedWithoutItems,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OrderSlotBanner(order: rows.single)),
      ),
    );
    expect(find.text('Requested 04 Oct 2026, 08:00 AM'), findsOneWidget);
    expect(find.text('Requested ASAP'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
