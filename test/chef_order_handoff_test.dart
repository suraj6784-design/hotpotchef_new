import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/widgets/chef_order_handoff.dart';
import 'package:hotpotchef_new/widgets/order_slot_banner.dart';

/// Confirmed Breakfast 4D6B2765: Delivery Partner, diner slot 04 Oct 2026 08:00.
/// The In Progress card already shows the slot and the 4-hour prepare sentence.
/// It must also show the dropoff, and a delivery note only when the order has
/// one. The diner phone stays on the call icon. The delivery PIN stays off
/// this card.
void main() {
  const dropoff = '9, Thergaon, Pimpri-Chinchwad, Maharashtra - 411033';
  const phone = '9876543210';
  const sentence = 'Opens in 14 hr 33 min (4 hours before requested time)';

  Map<String, dynamic> breakfast({
    String? customerPhone,
    String? specialInstructions,
    String? gateInstructions,
    String orderType = 'Delivery Partner',
    String? deliveryAddress = dropoff,
    String? deliveryOtp,
    List<Map<String, dynamic>>? itemNotes,
  }) {
    final items = [
      {
        'title': 'Breakfast',
        'quantity': 1,
        'exact_time': '8:00 AM to 9:00 AM',
        'time_slot': '8:00 AM to 9:00 AM',
        'selected_date': '2026-10-04',
        'selected_year': 2026,
        if (itemNotes != null) ...itemNotes.first,
      },
    ];
    return {
      'id': '4d6b2765-c401-4f1a-ae33-8c96c8c4f476',
      'status': 'Confirmed',
      'order_type': orderType,
      'created_at': DateTime(2026, 10, 3, 6, 57).toIso8601String(),
      'delivery_address': deliveryAddress,
      'customer_phone': ?customerPhone,
      'special_instructions': ?specialInstructions,
      'gate_instructions': ?gateInstructions,
      'delivery_otp': ?deliveryOtp,
      'items': jsonEncode(items),
    };
  }

  Future<void> pumpCard(WidgetTester tester, Map<String, dynamic> order) async {
    final start = orderSlotStart(order)!;
    final now = start.subtract(const Duration(hours: 18, minutes: 33));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ...chefKitchenOrderTiming(
                order: order,
                isPending: false,
                isPreparing: false,
                now: now,
              ),
              ChefOrderHandoffDetails(order: order),
            ],
          ),
        ),
      ),
    );
  }

  test('delivery handoff reads the stored dropoff and note, not the phone', () {
    final withNote = chefOrderHandoff(breakfast(
      customerPhone: phone,
      specialInstructions: 'Ring the bell\nDelivery PIN: 4821',
      gateInstructions: 'Tower A',
      deliveryOtp: '4821',
    ));
    expect(withNote.dropoff, dropoff);
    expect(withNote.note, contains('Ring the bell'));
    expect(withNote.note, contains('Gate: Tower A'));
    expect(withNote.note, isNot(contains('4821')));
    expect(withNote.note, isNot(contains('Delivery PIN')));
    expect(withNote.note, isNot(contains(phone)));
    expect(withNote.dropoff, isNot(contains(phone)));

    final bare = chefOrderHandoff(breakfast(customerPhone: phone, specialInstructions: ''));
    expect(bare.dropoff, dropoff);
    expect(bare.note, isEmpty);

    final pickup = chefOrderHandoff(breakfast(
      orderType: 'Customer Pickup',
      customerPhone: phone,
    ));
    expect(pickup.dropoff, isEmpty);
    expect(pickup.note, isEmpty);

    expect(kChefPrepEarliestMinutes, 240);
  });

  test('item instructions are included once and a repeated gate is not copied', () {
    final handoff = chefOrderHandoff(breakfast(
      specialInstructions: 'Gate: Tower A',
      gateInstructions: 'Tower A',
      itemNotes: [
        {'special_instructions': 'No onion'},
      ],
    ));
    expect(handoff.note, 'Gate: Tower A\nBreakfast: No onion');
    expect('Gate: Tower A'.allMatches(handoff.note).length, 1);
  });

  testWidgets('confirmed In Progress card shows the dropoff and hides the phone', (tester) async {
    await pumpCard(
      tester,
      breakfast(customerPhone: phone, deliveryOtp: '4821'),
    );

    expect(find.text('Dropoff: $dropoff'), findsOneWidget);
    expect(find.text('Phone: $phone'), findsNothing);
    expect(find.textContaining(phone), findsNothing);
    expect(find.textContaining('Phone:'), findsNothing);
    expect(find.textContaining('Note:'), findsNothing);
    expect(find.textContaining('4821'), findsNothing);
    expect(find.textContaining('Delivery PIN'), findsNothing);
    expect(find.text('Requested 04 Oct 2026, 08:00 AM'), findsOneWidget);
    expect(find.text(sentence), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a delivery note is shown and the prepare sentence stays once', (tester) async {
    await pumpCard(
      tester,
      breakfast(
        customerPhone: phone,
        specialInstructions: 'Leave with security',
        deliveryOtp: '8779',
      ),
    );

    expect(find.text('Dropoff: $dropoff'), findsOneWidget);
    expect(find.textContaining(phone), findsNothing);
    expect(find.textContaining('Phone:'), findsNothing);
    expect(find.textContaining('Note: Leave with security'), findsOneWidget);
    expect(find.textContaining('8779'), findsNothing);
    expect(find.text('Requested 04 Oct 2026, 08:00 AM'), findsOneWidget);
    expect(find.text(sentence), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a missing note is not invented and the phone stays hidden', (tester) async {
    await pumpCard(tester, breakfast(customerPhone: phone));

    expect(find.text('Dropoff: $dropoff'), findsOneWidget);
    expect(find.textContaining(phone), findsNothing);
    expect(find.textContaining('Phone:'), findsNothing);
    expect(find.textContaining('Note:'), findsNothing);
    expect(find.text(sentence), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
