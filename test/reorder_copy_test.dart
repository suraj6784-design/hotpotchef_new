import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/services/reorder_service.dart';

void main() {
  test('last successful order skips cancelled rows and empty carts', () {
    final last = lastSuccessfulOrder([
      {'id': '1', 'status': 'Cancelled', 'items': [{'title': 'Dal', 'meal_id': 'm1'}]},
      {'id': '2', 'status': 'Delivered', 'items': []},
      {
        'id': '3',
        'status': 'completed',
        'items': [
          {'title': 'Dal rice', 'meal_id': 'm2'},
          {'title': 'Raita', 'meal_id': 'm3'},
        ],
      },
    ]);
    expect(last?['id'], '3');
    expect(reorderMealSummary(orderItemsForReorder(last)), 'Dal rice + 1 more');
  });

  test('out for delivery is not a successful past order', () {
    expect(
      isSuccessfulPastOrder({'id': 'ofd', 'status': 'Out for Delivery', 'items': [{'title': 'Dal'}]}),
      isFalse,
    );
    expect(
      lastSuccessfulOrder([
        {'id': 'ofd', 'status': 'Out for Delivery', 'items': [{'title': 'Dal', 'meal_id': 'm1'}]},
        {'id': 'done', 'status': 'Delivered', 'items': [{'title': 'Dal', 'meal_id': 'm1'}]},
      ])?['id'],
      'done',
    );
  });

  test('same-as-last copy uses the weekday inside one week', () {
    final wednesday = DateTime(2026, 9, 2, 13);
    expect(sameAsLastLabel(wednesday, now: DateTime(2026, 9, 2, 20)), 'Same as earlier today');
    expect(sameAsLastLabel(wednesday, now: DateTime(2026, 9, 3)), 'Same as yesterday');
    expect(sameAsLastLabel(wednesday, now: DateTime(2026, 9, 6)), 'Same as last Wednesday');
    expect(sameAsLastLabel(wednesday, now: DateTime(2026, 9, 12)), 'Order again');
  });

  test('home banner hides once every last-order dish is already in the cart', () {
    final items = [
      {'title': 'Dal', 'meal_id': 'm2', 'id': 'line-1'},
      {'title': 'Raita', 'source_meal_id': 'm3'},
    ];
    expect(orderItemsAlreadyInCart(items, const ['m2']), isFalse);
    expect(orderItemsAlreadyInCart(items, const ['m2', 'm3']), isTrue);
    expect(catalogMealIdFromOrderItem(items.first), 'm2');
  });
}
