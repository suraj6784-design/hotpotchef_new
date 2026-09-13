// lib/utils/cart_merge.dart
//
// Union guest (local) cart lines with the signed-in user's remote cart.
// Remote-wins used to drop guest items whenever the account cart was
// non-empty — login after browsing as a guest must keep those lines.

import '../models/cart_state.dart';

abstract final class CartMerge {
  /// Meal identity plus a stable add-on signature (id + price, order-independent).
  static String lineKey(CartItemModel item) {
    final addonKey = item.selectedAddOns.map((a) => '${a.id}:${a.price}').toList()
      ..sort();
    return '${item.mealId}|${addonKey.join(',')}';
  }

  /// Merges [guest] into [remote].
  ///
  /// - Empty remote → guest is kept (push-up path).
  /// - Empty guest → remote is kept.
  /// - Same meal + add-ons → quantities are summed.
  /// - Same chef, different meals → union.
  /// - Different chefs → guest chef wins so login never discards the cart
  ///   the user just built; remote lines from other kitchens are dropped.
  static List<CartItemModel> merge({
    required List<CartItemModel> guest,
    required List<CartItemModel> remote,
  }) {
    if (guest.isEmpty) return List<CartItemModel>.of(remote);
    if (remote.isEmpty) return List<CartItemModel>.of(guest);

    final guestChefIds = guest.map((item) => item.chefId).toSet();
    final remoteChefs = remote.map((item) => item.chefId).toSet();
    final sharedChefs = guestChefIds.intersection(remoteChefs);

    final remoteToMerge = sharedChefs.isEmpty
        ? const <CartItemModel>[]
        : remote.where((item) => sharedChefs.contains(item.chefId)).toList();

    final byKey = <String, CartItemModel>{};
    for (final item in remoteToMerge) {
      byKey[lineKey(item)] = item;
    }
    for (final item in guest) {
      final key = lineKey(item);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = item;
      } else {
        byKey[key] = existing.copyWith(quantity: existing.quantity + item.quantity);
      }
    }
    return byKey.values.toList(growable: false);
  }
}
