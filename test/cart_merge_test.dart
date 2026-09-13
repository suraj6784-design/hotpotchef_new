import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/cart_enums.dart';
import 'package:hotpotchef_new/models/cart_state.dart';
import 'package:hotpotchef_new/utils/cart_merge.dart';

CartItemModel _item({
  required String id,
  required String mealId,
  required String chefId,
  required int quantity,
  List<CartItemAddOn> addOns = const [],
}) {
  return CartItemModel(
    id: id,
    mealId: mealId,
    chefId: chefId,
    title: 'Meal $mealId',
    basePrice: 100,
    quantity: quantity,
    scheduledDate: DateTime.utc(2026, 1, 1),
    serviceType: ServiceType.deliveryPlatform,
    selectedAddOns: addOns,
  );
}

void main() {
  group('CartMerge.merge', () {
    test('keeps guest lines when the remote cart is empty', () {
      final guest = [_item(id: 'g1', mealId: 'm1', chefId: 'c1', quantity: 2)];
      final merged = CartMerge.merge(guest: guest, remote: const []);
      expect(merged, guest);
    });

    test('keeps remote lines when the guest cart is empty', () {
      final remote = [_item(id: 'r1', mealId: 'm2', chefId: 'c1', quantity: 1)];
      final merged = CartMerge.merge(guest: const [], remote: remote);
      expect(merged, remote);
    });

    test('sums quantities for the same meal id and add-ons', () {
      final guest = [_item(id: 'g1', mealId: 'm1', chefId: 'c1', quantity: 2)];
      final remote = [_item(id: 'r1', mealId: 'm1', chefId: 'c1', quantity: 3)];
      final merged = CartMerge.merge(guest: guest, remote: remote);
      expect(merged, hasLength(1));
      expect(merged.single.mealId, 'm1');
      expect(merged.single.quantity, 5);
      expect(merged.single.id, 'r1');
    });

    test('unions different meal ids from the same chef', () {
      final guest = [_item(id: 'g1', mealId: 'm-guest', chefId: 'c1', quantity: 1)];
      final remote = [_item(id: 'r1', mealId: 'm-remote', chefId: 'c1', quantity: 2)];
      final merged = CartMerge.merge(guest: guest, remote: remote);
      expect(merged.map((i) => i.mealId).toSet(), {'m-guest', 'm-remote'});
      expect(merged.fold<int>(0, (sum, i) => sum + i.quantity), 3);
    });

    test('treats the same meal with different add-ons as separate lines', () {
      const extra = CartItemAddOn(id: 'extra', title: 'Raita', price: 20);
      final guest = [
        _item(id: 'g1', mealId: 'm1', chefId: 'c1', quantity: 1, addOns: [extra]),
      ];
      final remote = [_item(id: 'r1', mealId: 'm1', chefId: 'c1', quantity: 1)];
      final merged = CartMerge.merge(guest: guest, remote: remote);
      expect(merged, hasLength(2));
    });

    test('preserves guest lines when remote belongs to a different chef', () {
      final guest = [_item(id: 'g1', mealId: 'm-guest', chefId: 'chef-a', quantity: 1)];
      final remote = [_item(id: 'r1', mealId: 'm-remote', chefId: 'chef-b', quantity: 4)];
      final merged = CartMerge.merge(guest: guest, remote: remote);
      expect(merged, hasLength(1));
      expect(merged.single.mealId, 'm-guest');
      expect(merged.single.chefId, 'chef-a');
    });
  });
}
