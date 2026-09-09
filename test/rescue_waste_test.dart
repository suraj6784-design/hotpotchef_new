import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('pre-order waste helpers', () {
    test('counts slotted plates and skips ASAP / cancelled orders', () {
      expect(orderIsPreOrderSlot({'time_slot': '7:30 PM'}), isTrue);
      expect(orderIsPreOrderSlot({'time_slot': 'ASAP'}), isFalse);
      expect(orderIsPreOrderSlot({'time_slot': 'now'}), isFalse);
      expect(
        orderIsPreOrderSlot({'selected_date': '2026-09-07', 'time_slot': 'ASAP'}),
        isFalse,
      );
      expect(orderLineIsRescuePlate({'offer_type': 'flashSale'}), isTrue);

      expect(
        preOrderedPlatesFromOrderItems([
          {'time_slot': '7:30 PM', 'quantity': 2},
          {'time_slot': 'ASAP', 'quantity': 5},
          {'time_slot': '9:00 AM', 'quantity': 1},
        ]),
        3,
      );

      expect(
        preOrderedPlatesFromOrders([
          {
            'status': 'Preparing',
            'items': [
              {'time_slot': '6:30 PM', 'quantity': 2},
            ],
          },
          {
            'status': 'Cancelled by Customer',
            'items': [
              {'time_slot': '6:30 PM', 'quantity': 4},
            ],
          },
          {
            'status': 'Delivered',
            'items':
                '[{"time_slot":"9:00 AM","quantity":1},{"time_slot":"ASAP","quantity":9}]',
          },
        ]),
        3,
      );
    });

    test('builds cook-to-demand publicity copy', () {
      expect(
        rescuedMealsHeadline(rescuedPlates: 12, onOfferPlates: 3),
        'Saved from waste · 12 plates pre-ordered',
      );
      expect(
        rescuedMealsHeadline(rescuedPlates: 1, onOfferPlates: 0),
        'Saved from waste · 1 plate pre-ordered',
      );
      expect(
        rescuedMealsHeadline(rescuedPlates: 0, onOfferPlates: 5),
        '5 slotted meals ready to pre-order',
      );
      expect(
        rescuedMealsSubhead(rescuedPlates: 4, onOfferPlates: 2),
        contains('booked demand'),
      );
      expect(
        rescuedMealsSubhead(rescuedPlates: 0, onOfferPlates: 3),
        contains('Book a time slot'),
      );
    });
  });
}
