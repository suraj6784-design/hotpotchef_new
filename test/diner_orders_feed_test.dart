import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/diner_orders_feed.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

/// Order 4d6b2765: Arushi's paid Breakfast, chef-accepted, slot 4 Oct 2026 8:00 AM.
/// Active used to paint catering cards first, so this confirmed row never
/// appeared in the viewport. A status-only accept also drops toasted `items`.
void main() {
  const orderId = '4d6b2765-c401-4f1a-ae33-8c96c8c4f476';
  const arushiId = '93144983-924c-4c9e-b185-b87dab08af89';
  final items = jsonEncode([
    {
      'title': 'Breakfast',
      'quantity': 1,
      'price': 90,
      'exact_time': '8:00 AM to 9:00 AM',
      'time_slot': '8:00 AM to 9:00 AM',
      'chef_schedule': 'Daily (8:00 AM to 11:30 AM)',
      'selected_date': '2026-10-04',
      'selected_year': 2026,
      'chef_name': 'newchef16',
      'service_type': 'Delivery Partner',
      'rawMealDetails': {
        'title': 'Breakfast',
        'time_slot': 'Daily (8:00 AM to 11:30 AM)',
        'exact_time': '8:00 AM to 9:00 AM',
      },
    },
  ]);

  Map<String, dynamic> breakfast({String status = 'Confirmed'}) {
    return {
      'id': orderId,
      'customer_id': arushiId,
      'customer_phone': '9876543210',
      'status': status,
      'created_at': '2026-10-03T06:57:27.791921Z',
      'promised_at': '2026-10-04T02:30:00Z',
      'order_type': 'Delivery Partner',
      'items': items,
    };
  }

  test('confirmed Breakfast stays on Active for this diner and off Past', () {
    final row = breakfast();
    final cancelledBreakfast = {
      'id': '695b9cd2-11d4-49ce-8d88-70a412d1d117',
      'customer_id': arushiId,
      'status': 'Cancelled',
      'items': jsonEncode([
        {'title': 'Breakfast', 'quantity': 1},
      ]),
    };
    final cancelledBiryani = {
      'id': '83ed8112-c9d3-48b3-9ba3-216fd87e0175',
      'customer_id': arushiId,
      'status': 'Cancelled',
      'items': jsonEncode([
        {'title': 'Veg Biryani', 'quantity': 9},
      ]),
    };
    final samePhoneOtherDiner = {
      'id': 'other-diner-order',
      'customer_id': 'fad1d06a-868a-4aff-8da4-4e4b18b6fa4a',
      'customer_phone': '9876543210',
      'status': 'Confirmed',
      'items': items,
    };

    final mine = [
      row,
      cancelledBreakfast,
      cancelledBiryani,
      samePhoneOtherDiner,
    ].where((order) => dinerOrderOwnedBy(order, arushiId));

    expect(dinerActiveOrders(mine).map((order) => order['id']), [orderId]);
    expect(dinerPastOrders(mine).map((order) => order['id']), [
      '695b9cd2-11d4-49ce-8d88-70a412d1d117',
      '83ed8112-c9d3-48b3-9ba3-216fd87e0175',
    ]);
    expect(dinerOrderLineLabel(row), '1x Breakfast');
    expect(formatOrderId(orderId, orderId), '4D6B2765');
    expect(formatDeliverySlotLabel(row), '04 Oct 2026, 08:00 AM');
    expect(row['promised_at'], '2026-10-04T02:30:00Z');
    expect(kChefPrepEarliestMinutes, 240);
  });

  test(
    'accept that drops toasted items still lists Breakfast on the booked slot',
    () {
      final placed = breakfast(status: 'Pending Chef Approval');
      final acceptedWithoutItems = {
        ...breakfast(status: 'Confirmed'),
        'items': null,
      };

      expect(dinerOrderLineLabel(acceptedWithoutItems), '1x Custom Order');
      expect(formatDeliverySlotLabel(acceptedWithoutItems), 'ASAP');

      final merged = mergeDinerOrderSnapshot([placed], [acceptedWithoutItems]);
      final active = dinerActiveOrders(merged);
      expect(active.single['status'], 'Confirmed');
      expect(active.single['items'], items);
      expect(active.single['promised_at'], '2026-10-04T02:30:00Z');
      expect(dinerOrderLineLabel(active.single), '1x Breakfast');
      expect(formatDeliverySlotLabel(active.single), '04 Oct 2026, 08:00 AM');
      expect(
        canChefStartPreparing(
          active.single,
          now: DateTime.utc(2026, 10, 3, 8, 3),
        ),
        isFalse,
      );
    },
  );

  test('Active lists meal orders before catering', () {
    expect(
      dinerOrdersSections(
        showPast: false,
        hasMealOrders: true,
        hasBroadcasts: true,
      ),
      [
        DinerOrdersSection.reorder,
        DinerOrdersSection.meals,
        DinerOrdersSection.broadcasts,
      ],
    );
    expect(
      dinerOrdersSections(
        showPast: false,
        hasMealOrders: false,
        hasBroadcasts: true,
      ),
      [
        DinerOrdersSection.reorder,
        DinerOrdersSection.broadcasts,
        DinerOrdersSection.empty,
      ],
    );
    expect(
      dinerOrdersSections(
        showPast: true,
        hasMealOrders: true,
        hasBroadcasts: true,
      ),
      [DinerOrdersSection.meals],
    );
  });

  testWidgets('confirmed Breakfast is above My broadcasts on Active', (
    tester,
  ) async {
    final row = breakfast();
    final sections = dinerOrdersSections(
      showPast: false,
      hasMealOrders: true,
      hasBroadcasts: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (final section in sections)
                if (section == DinerOrdersSection.meals)
                  Text(dinerOrderLineLabel(row))
                else if (section == DinerOrdersSection.broadcasts)
                  const Text('My broadcasts & catering')
                else
                  const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );

    expect(find.text('1x Breakfast'), findsOneWidget);
    expect(find.text('My broadcasts & catering'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('1x Breakfast')).dy,
      lessThan(tester.getTopLeft(find.text('My broadcasts & catering')).dy),
    );
  });
}
