import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('checkoutCartPayload specialty flags', () {
    test('keeps hamper / society / shelf flags for place_customer_order', () {
      final payload = checkoutCartPayload([
        {
          'chef_id': 'chef-1',
          'title': 'Diwali Box',
          'quantity': 1,
          'price': 499,
          'is_hamper': true,
          'is_society_night': true,
          'society_label': 'Green Valley A',
          'is_shelf_item': true,
          'shelf_kind': 'Pickle',
          'rawMealDetails': {
            'id': 'meal-1',
            'chef_id': 'chef-1',
            'price': 499,
          },
        },
      ]);

      expect(payload, hasLength(1));
      expect(payload.single['is_hamper'], isTrue);
      expect(payload.single['is_society_night'], isTrue);
      expect(payload.single['society_label'], 'Green Valley A');
      expect(payload.single['is_shelf_item'], isTrue);
      expect(payload.single['shelf_kind'], 'Pickle');
      expect(payload.single['rawMealDetails']['is_hamper'], isTrue);
      expect(orderLineSpecialtyTag(payload.single), isNotNull);
    });
  });

  group('society group checkout note', () {
    test('merges place / drop / slot into kitchen instructions', () {
      expect(
        societyGroupCheckoutNote(
          placeKind: 'society',
          placeLabel: 'Green Valley A',
          dropoffNote: 'Gate 2',
          timeSlot: '19:30',
          roomCode: 'ABCD',
        ),
        contains('Green Valley A'),
      );

      final merged = mergedOrderInstructions(
        [
          {'title': 'Thali', 'specialInstructions': 'Less spicy'},
        ],
        null,
        {
          'placeKind': 'society',
          'placeLabel': 'Green Valley A',
          'dropoffNote': 'Gate 2',
          'timeSlot': '19:30',
          'roomCode': 'ABCD',
        },
      );
      expect(merged, contains('Group'));
      expect(merged, contains('Gate 2'));
      expect(merged, contains('Thali: Less spicy'));
    });

    test('warns when society night label mismatches drop', () {
      expect(
        societyNightAddressMismatchWarning(
          cartItems: [
            {
              'is_society_night': true,
              'society_label': 'Green Valley A',
              'title': 'Night thali',
            },
          ],
          sharedPlaceLabel: 'Sunrise Towers',
          deliveryAddress: 'Sunrise Towers, Pune',
        ),
        contains('Green Valley A'),
      );
      expect(
        societyNightAddressMismatchWarning(
          cartItems: [
            {
              'is_society_night': true,
              'society_label': 'Green Valley A',
              'title': 'Night thali',
            },
          ],
          sharedPlaceLabel: 'Green Valley A wing B',
          deliveryAddress: null,
        ),
        isNull,
      );
    });
  });

  group('packagingFeeForCartItems', () {
    test('zeros shelf-only and caps hamper-only', () {
      expect(
        packagingFeeForCartItems([
          {'is_shelf_item': true, 'title': 'Mango pickle'},
        ], loyaltyTierFee: 20),
        0,
      );
      expect(
        packagingFeeForCartItems([
          {'is_hamper': true, 'title': 'Diwali box'},
        ], loyaltyTierFee: 20),
        10,
      );
      expect(
        packagingFeeForCartItems([
          {'title': 'Dal rice', 'category': 'Maharashtrian'},
        ], loyaltyTierFee: 20),
        20,
      );
    });
  });

  group('mealInDeliveryRadius', () {
    test('filters far kitchens and keeps unknown pins', () {
      expect(
        mealInDeliveryRadius(
          {'pickup_lat': 18.52, 'pickup_lng': 73.85},
          destinationLat: 18.52,
          destinationLng: 73.85,
        ),
        isTrue,
      );
      expect(
        mealInDeliveryRadius(
          {'pickup_lat': 19.07, 'pickup_lng': 72.87}, // Mumbai vs Pune-ish
          destinationLat: 18.52,
          destinationLng: 73.85,
        ),
        isFalse,
      );
      expect(
        mealInDeliveryRadius(
          {'title': 'No pin'},
          destinationLat: 18.52,
          destinationLng: 73.85,
        ),
        isTrue,
      );
    });
  });
}
