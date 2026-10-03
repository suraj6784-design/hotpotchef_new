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
  });
}
