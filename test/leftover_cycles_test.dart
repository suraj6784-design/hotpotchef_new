import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/app_role.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('catering lead geo', () {
    test('keeps a lead with no pin and hides one beyond 25 km', () {
      expect(isCateringLeadInRange({'title': 'Office lunch'}), isTrue);
      expect(
        isCateringLeadInRange(
          {'latitude': 18.52, 'longitude': 73.85},
          {'lat': 18.52, 'lng': 73.86},
        ),
        isTrue,
      );
      expect(
        isCateringLeadInRange(
          {'latitude': 19.07, 'longitude': 72.87},
          {'lat': 18.52, 'lng': 73.85},
        ),
        isFalse,
      );
    });
  });

  group('canPaySharedCart', () {
    test('only the known host can pay a group cart', () {
      expect(canPaySharedCart(roomCode: null, userId: 'a'), isTrue);
      expect(canPaySharedCart(roomCode: 'GRP-1', hostId: 'host', userId: 'host'), isTrue);
      expect(canPaySharedCart(roomCode: 'GRP-1', hostId: 'host', userId: 'guest'), isFalse);
      expect(canPaySharedCart(roomCode: 'GRP-1', hostId: null, userId: 'guest'), isTrue);
    });
  });

  group('favoriteCategoryFromPastItems', () {
    test('picks the category the diner ordered most', () {
      expect(
        favoriteCategoryFromPastItems([
          {'category': 'Punjabi'},
          {'category': 'Maharashtrian'},
          {'category': 'Punjabi'},
        ]),
        'Punjabi',
      );
      expect(favoriteCategoryFromPastItems(const []), isNull);
    });
  });

  group('packagingOrderTotal', () {
    test('multiplies pack price by quantity', () {
      expect(packagingOrderTotal(250, 2), 500);
      expect(packagingOrderTotal(180, 0), 180);
    });
  });

  group('packaging supply requests', () {
    test('marks Packaging service_type as a supply request', () {
      expect(
        isPackagingSupplyRequest({'service_type': 'Packaging', 'status': 'Pending'}),
        isTrue,
      );
      expect(
        isPackagingSupplyRequest({'service_type': 'Delivery Partner', 'status': 'Open'}),
        isFalse,
      );
    });

    test('is chef-only', () {
      expect(AppRole.chef.canUsePackagingStore, isTrue);
      expect(AppRole.customer.canUsePackagingStore, isFalse);
      expect(AppRole.driver.canUsePackagingStore, isFalse);
    });

    test('builds a customer_requests payload, not a packaging_orders row', () {
      final payload = packagingSupplyRequestPayload(
        chefId: 'chef-1',
        chefName: 'Asha',
        chefEmail: 'asha@example.com',
        chefPhone: '9999999999',
        kitchenAddress: '12 Kitchen Lane',
        title: 'Eco-Friendly Meal Box (500ml)',
        requestId: 'SUP-ABC123',
        sku: 'm1',
        description: 'Pack of 50.',
        quantity: 2,
        unitPrice: 250,
      );
      expect(payload['customer_id'], 'chef-1');
      expect(payload['service_type'], 'Packaging');
      expect(payload['request_type'], 'packaging');
      expect(payload['status'], 'Open');
      expect(payload['target_date_time'], isNotEmpty);
      expect(payload['budget'], 500);
      expect(payload['description'], contains('SUP-ABC123'));
      expect(packagingRequestDisplayId(payload), 'SUP-ABC123');
    });

    test('marks open catalog items as Requested until fulfilled', () {
      final open = packagingSupplyRequestPayload(
        chefId: 'chef-1',
        chefName: 'Asha',
        chefEmail: 'asha@example.com',
        chefPhone: '9999999999',
        kitchenAddress: '12 Kitchen Lane',
        title: 'Branded Paper Carry Bags',
        requestId: 'SUP-QO3FDZ',
        sku: 'm4',
        description: 'Pack of 50.',
        quantity: 1,
        unitPrice: 300,
      );
      expect(isOpenPackagingSupplyRequest(open), isTrue);
      expect(
        packagingCatalogItemRequested([open], {'id': 'm4', 'title': 'Branded Paper Carry Bags'}),
        isTrue,
      );
      expect(
        packagingCatalogItemRequested([
          {...open, 'status': 'Cancelled'},
        ], {'id': 'm4', 'title': 'Branded Paper Carry Bags'}),
        isFalse,
      );
    });
  });

  group('chef prep window', () {
    test('unlocks Start Preparing 2 hours before a scheduled slot', () {
      final placed = DateTime(2026, 9, 5, 8);
      final order = {
        'created_at': placed.toIso8601String(),
        'time_slot': '05/09/2026 | 8:00 PM',
      };
      expect(canChefStartPreparing(order, now: DateTime(2026, 9, 5, 10)), isFalse);
      expect(canChefStartPreparing(order, now: DateTime(2026, 9, 5, 18, 10)), isTrue);
      expect(canChefStartPreparing(order, now: DateTime(2026, 9, 5, 20, 10)), isTrue);
      expect(canChefStartPreparing({'time_slot': 'ASAP'}, now: DateTime(2026, 9, 5, 10)), isTrue);
    });

    test('diner promised slot counts down until the order is done', () {
      final now = DateTime(2026, 9, 6, 18, 0);
      final order = {
        'status': 'Preparing',
        'created_at': DateTime(2026, 9, 6, 10).toIso8601String(),
        'time_slot': '06/09/2026 | 8:00 PM',
        'selected_date': '06/09/2026',
      };
      expect(dinerSlotCountdownActive('Preparing'), isTrue);
      expect(dinerSlotCountdownActive('Out for Delivery'), isTrue);
      expect(dinerSlotCountdownActive('Delivered'), isFalse);
      expect(dinerSlotIsLate(order, now: now), isFalse);
      expect(dinerPromisedSlotCopy(order, now: now), contains('left'));
      expect(dinerPromisedSlotCopy(order, now: now), contains('8:00 PM'));
      expect(dinerPromisedSlotCopy({...order, 'status': 'Delivered'}, now: now), '');
      expect(
        dinerPromisedSlotCopy(order, now: DateTime(2026, 9, 6, 20, 10)),
        contains('late'),
      );
    });

    test('reads the requested slot from line items', () {
      final order = {
        'created_at': DateTime(2026, 9, 5, 8).toIso8601String(),
        'items': [
          {'time_slot': '05/09/2026 | 8:00 PM', 'selected_date': '05/09/2026'},
        ],
      };
      expect(formatDeliverySlotLabel(order), contains('8:00 PM'));
      expect(canChefStartPreparing(order, now: DateTime(2026, 9, 5, 10)), isFalse);
    });
  });

  group('app date format', () {
    test('placed and delivery slot share dd MMM yyyy, hh:mm a', () {
      final placed = DateTime(2026, 9, 6, 1, 31);
      expect(formatAppDateTime(placed), '06 Sep 2026, 01:31 AM');
      expect(formatOrderDate(placed.toIso8601String()), '06 Sep 2026, 01:31 AM');
      expect(
        smartTimeSlot('9:00 AM', placed, selectedDateStr: '06/09/2026'),
        '06 Sep 2026, 09:00 AM',
      );
      expect(
        formatDeliverySlotLabel({
          'created_at': placed.toIso8601String(),
          'time_slot': '06/09/2026 | 9:00 AM',
          'selected_date': '06/09/2026',
        }),
        '06 Sep 2026, 09:00 AM',
      );
      expect(
        formatDeliverySlotLabel({
          'created_at': placed.toIso8601String(),
          'items': [
            {'time_slot': '9:00 AM', 'selected_date': '2026-09-06'},
          ],
        }),
        '06 Sep 2026, 09:00 AM',
      );
    });

    test('diner hourly cart slots stay promised, not ASAP', () {
      final placed = DateTime(2026, 9, 9, 10, 44);
      expect(looksLikeChefServingWindow('10:00 AM to 11:00 AM'), isFalse);
      expect(looksLikeChefServingWindow('Sat, Sun (9:00 AM to 11:00 PM)'), isTrue);
      expect(looksLikeChefServingWindow('Today (9:00 AM to 11:00 PM)'), isTrue);
      expect(
        formatDeliverySlotLabel({
          'created_at': placed.toIso8601String(),
          'time_slot': '10:00 AM to 11:00 AM',
          'selected_date': '2026-09-09',
        }, now: placed),
        'Sep 9th 2026, 10:00 AM to 11:00 AM',
      );
    });

    test('nested mealDetails kitchen window is used only when no diner hour exists', () {
      final placed = DateTime(2026, 9, 7, 11, 32);
      expect(
        formatDeliverySlotLabel({
          'created_at': placed.toIso8601String(),
          'time_slot': 'ASAP',
          'items': [
            {
              'title': 'New Gulab Jamun',
              'time_slot': 'ASAP',
              'mealDetails': {'time_slot': 'Today (9:00 AM to 9:00 PM)'},
            },
          ],
        }, now: placed),
        'Sep 7th 2026, 9:00 AM to 9:00 PM',
      );
    });

    test('customer selected hour beats chef serving window', () {
      final placed = DateTime(2026, 9, 9, 9, 15);
      final order = {
        'created_at': placed.toIso8601String(),
        'time_slot': 'ASAP',
        'items': [
          {
            'exact_time': '10:00 AM to 11:00 AM',
            'timeSlot': '10:00 AM to 11:00 AM',
            'time_slot': 'Today (9:00 AM to 11:00 PM)',
            'selected_date': '2026-09-09',
            'mealDetails': {'time_slot': 'Today (9:00 AM to 11:00 PM)'},
          },
        ],
      };
      expect(formatDeliverySlotLabel(order, now: placed), 'Sep 9th 2026, 10:00 AM to 11:00 AM');
    });

    test('stored slot date always includes the year', () {
      final fields = storedSlotDateFields(
        {'selected_date': '9 Sep'},
        now: DateTime(2026, 9, 9),
      );
      expect(fields['selected_date'], '2026-09-09');
      expect(fields['selected_year'], 2026);
      expect(
        formatDeliverySlotLabel({
          'created_at': DateTime(2027, 1, 1).toIso8601String(),
          'time_slot': '10:00 AM to 11:00 AM',
          'selected_date': '9 Sep',
          'selected_year': 2026,
        }),
        'Sep 9th 2026, 10:00 AM to 11:00 AM',
      );
    });

    test('checkout payload stores the diner hour, not ASAP', () {
      final lines = checkoutCartPayload([
        {
          'title': 'Veg Thali',
          'quantity': 1,
          'price': 70,
          'timeSlot': '10:00 AM to 11:00 AM',
          'time_slot': '10:00 AM to 11:00 AM',
          'exact_time': '10:00 AM to 11:00 AM',
          'selected_date': '2026-09-09',
          'rawMealDetails': {
            'time_slot': 'Today (9:00 AM to 11:00 PM)',
            'exact_time': '10:00 AM to 11:00 AM',
          },
        },
      ]);
      expect(lines.first['selected_date'], '2026-09-09');
      expect(lines.first['selected_year'], 2026);
      expect(lines.first['time_slot'], '10:00 AM to 11:00 AM');
      expect(lines.first['exact_time'], '10:00 AM to 11:00 AM');
      expect(
        formatDeliverySlotLabel({
          'created_at': DateTime(2026, 9, 9, 11, 25).toIso8601String(),
          'items': lines,
        }),
        'Sep 9th 2026, 10:00 AM to 11:00 AM',
      );
    });

    test('ASAP line with chef_schedule still shows the kitchen window', () {
      expect(
        formatDeliverySlotLabel({
          'created_at': DateTime(2026, 9, 9, 11, 25).toIso8601String(),
          'items': [
            {
              'title': 'Veg Thali',
              'time_slot': 'ASAP',
              'chef_schedule': 'Today (9:00 AM to 11:00 PM)',
            },
          ],
        }),
        'Sep 9th 2026, 9:00 AM to 11:00 PM',
      );
    });

    test('kitchen serving hours show only when no hourly slot was booked', () {
      final placed = DateTime(2026, 9, 7, 20, 56);
      expect(
        formatDeliverySlotLabel({
          'created_at': placed.toIso8601String(),
          'items': [
            {
              'time_slot': 'Sat, Sun (9:00 AM to 11:00 PM)',
              'selected_date': '2026-09-07',
            },
          ],
        }, now: placed),
        'Sep 7th 2026, 9:00 AM to 11:00 PM',
      );
    });
  });

  group('lineItemUnitPrice', () {
    test('prefers snapshotted discounted_price over camelCase list price', () {
      expect(
        lineItemUnitPrice({
          'discounted_price': 80,
          'discountedPrice': 999,
          'basePrice': 100,
          'price': 100,
          'quantity': 1,
        }),
        80,
      );
    });
  });
}
