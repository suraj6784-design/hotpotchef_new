import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/cart_enums.dart';
import 'package:hotpotchef_new/models/cart_state.dart';
import 'package:hotpotchef_new/services/shared_cart_service.dart';

CartItemModel _plate({
  required String id,
  String? ownerId,
  String? ownerName,
  int quantity = 1,
}) {
  return CartItemModel(
    id: id,
    mealId: id,
    chefId: 'chef',
    title: id,
    basePrice: 90,
    quantity: quantity,
    scheduledDate: DateTime.utc(2026, 9, 26),
    serviceType: ServiceType.deliveryPlatform,
    addedByUserId: ownerId,
    addedByName: ownerName,
  );
}

void main() {
  test('a diner can edit only the plates they added', () {
    final mine = _plate(id: 'mine', ownerId: 'user-a', ownerName: 'Asha');
    final theirs = _plate(id: 'theirs', ownerId: 'user-b', ownerName: 'Bela');
    final legacy = _plate(id: 'legacy');

    expect(sharedCartLineEditable(mine, userId: 'user-a', hostId: 'user-a'), isTrue);
    expect(sharedCartLineEditable(theirs, userId: 'user-a', hostId: 'user-a'), isFalse);
    expect(sharedCartLineEditable(legacy, userId: 'user-a', hostId: 'user-a'), isTrue);
    expect(sharedCartLineEditable(legacy, userId: 'user-b', hostId: 'user-a'), isFalse);
    expect(groupPlateOwnerLabel(mine, userId: 'user-a', hostId: 'user-a'), 'You');
    expect(groupPlateOwnerLabel(theirs, userId: 'user-a', hostId: 'user-a'), 'Bela');
    expect(groupPlateOwnerLabel(legacy, userId: 'user-b', hostId: 'user-a'), 'Host');
  });

  test('saving a group cart keeps teammates plates and applies own edits', () {
    final remote = [
      _plate(id: 'host', ownerId: 'host', ownerName: 'Host', quantity: 1),
      _plate(id: 'mine', ownerId: 'me', ownerName: 'Me', quantity: 1),
    ];
    final local = [
      _plate(id: 'mine', ownerId: 'me', ownerName: 'Me', quantity: 2),
      _plate(id: 'new', ownerId: 'me', ownerName: 'Me'),
    ];

    final merged = mergeSharedCartItems(
      remote: remote,
      local: local,
      userId: 'me',
      hostId: 'host',
    );

    expect(merged.map((item) => item.id).toList(), ['host', 'mine', 'new']);
    expect(merged[0].quantity, 1);
    expect(merged[1].quantity, 2);
  });
}
