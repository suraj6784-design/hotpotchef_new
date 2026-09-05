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
      expect(payload['status'], 'Pending');
      expect(payload['budget'], 500);
      expect(payload['description'], contains('SUP-ABC123'));
      expect(packagingRequestDisplayId(payload), 'SUP-ABC123');
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
