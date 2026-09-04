import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/services/reorder_service.dart';

void main() {
  group('sold-out checkout copy', () {
    test('detects server sold_out code', () {
      expect(isSoldOutCheckoutError(null, {'code': 'sold_out'}), isTrue);
      expect(isSoldOutCheckoutError('network'), isFalse);
    });

    test('detects meal no longer available', () {
      expect(isSoldOutCheckoutError('One or more meals are no longer available'), isTrue);
    });

    test('does not mention a charge when stock is held before payment', () {
      expect(
        soldOutCheckoutMessage(charged: false),
        contains('Nothing was charged'),
      );
    });

    test('explains refund when capture already happened', () {
      expect(
        soldOutCheckoutMessage(charged: true, refunded: true),
        contains('refunded'),
      );
    });
  });

  group('checkoutCartPayload', () {
    test('keeps chef and meal ids without spreading the cart line id as a meal id', () {
      final payload = checkoutCartPayload([
        {
          'id': 'line_not_a_uuid',
          'chef_id': '11111111-1111-1111-1111-111111111111',
          'meal_id': '22222222-2222-2222-2222-222222222222',
          'title': 'AnyDish',
          'quantity': 1,
          'price': 221,
          'chef_name': 'newchef16',
        },
      ]);
      expect(payload.single['chef_id'], '11111111-1111-1111-1111-111111111111');
      expect(payload.single['source_meal_id'], '22222222-2222-2222-2222-222222222222');
      expect(payload.single.containsKey('rawMealDetails'), isFalse);
    });
  });

  group('checkoutErrorMessage', () {
    test('strips the Exception prefix from record failures', () {
      expect(
        checkoutErrorMessage(Exception('We could not record this order, so the payment was refunded. It should return in 5–7 business days.')),
        'We could not record this order, so the payment was refunded. It should return in 5–7 business days.',
      );
    });
  });

  group('isMealReorderable', () {
    test('rejects sold out, paused, and empty stock', () {
      expect(ReorderService.isMealReorderable(null), isFalse);
      expect(ReorderService.isMealReorderable({'status': 'sold out', 'quantity': 3}), isFalse);
      expect(ReorderService.isMealReorderable({'status': 'Paused', 'quantity': 3}), isFalse);
      expect(ReorderService.isMealReorderable({'status': 'Available', 'quantity': 0}), isFalse);
    });

    test('accepts a live dish with stock', () {
      expect(ReorderService.isMealReorderable({'status': 'Available', 'quantity': 2}), isTrue);
    });

    test('suggests other live dishes and names them in the snackbar', () {
      final alts = ReorderService.alternativeTitles(
        [
          {'id': 'gone', 'title': 'Butter chicken', 'status': 'Available', 'quantity': 2},
          {'id': 'alt-1', 'title': 'Dal tadka', 'status': 'Available', 'quantity': 4},
          {'id': 'alt-2', 'title': 'Jeera rice', 'status': 'Available', 'quantity': 6},
          {'id': 'paused', 'title': 'Paused dish', 'status': 'Paused', 'quantity': 5},
        ],
        excludeMealIds: {'gone'},
      );
      expect(alts, ['Dal tadka', 'Jeera rice']);
      expect(
        ReorderService.resultMessage(
          const ReorderResult(added: 0, skipped: ['Butter chicken'], alternatives: ['Dal tadka', 'Jeera rice']),
        ),
        'Butter chicken is no longer available to reorder. Try: Dal tadka, Jeera rice.',
      );
    });
  });
}
