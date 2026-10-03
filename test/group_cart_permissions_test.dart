import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/cart_enums.dart';
import 'package:hotpotchef_new/models/cart_state.dart';
import 'package:hotpotchef_new/services/shared_cart_service.dart';

CartItemModel _plate({
  required String id,
  required String mealId,
  required String ownerId,
  String? ownerName,
  int quantity = 1,
  String? timeSlot = '1:00 PM',
  List<CartItemAddOn> addOns = const [],
}) {
  return CartItemModel(
    id: id,
    mealId: mealId,
    chefId: 'chef',
    title: 'Veg Jumbo Thali',
    basePrice: 180,
    quantity: quantity,
    scheduledDate: DateTime.utc(2026, 10, 3),
    serviceType: ServiceType.deliveryPlatform,
    timeSlot: timeSlot,
    selectedAddOns: addOns,
    addedByUserId: ownerId,
    addedByName: ownerName,
  );
}

void main() {
  const salad = CartItemAddOn(id: 'salad', title: 'Salad', price: 30);

  test('a guest adding a meal the host already has creates their own line', () {
    final hostLine = _plate(
      id: 'host-line',
      mealId: 'thali',
      ownerId: 'kiranag',
      ownerName: 'Kiranag',
    );
    final added = addOwnedGroupPlate(
      items: [hostLine],
      plate: _plate(
        id: 'incoming',
        mealId: 'thali',
        ownerId: 'kiranag',
        quantity: 1,
        timeSlot: '7:00 PM',
      ),
      userId: 'arushi',
      userName: 'Arushi',
      hostId: 'kiranag',
      roomTimeSlot: '1:00 PM',
    );

    expect(added, hasLength(2));
    expect(added.first.id, 'host-line');
    expect(added.first.quantity, 1);
    expect(added.first.addedByUserId, 'kiranag');
    expect(added.first.addedByName, 'Kiranag');
    expect(added.first.timeSlot, '1:00 PM');
    expect(added.last.addedByUserId, 'arushi');
    expect(added.last.addedByName, 'Arushi');
    expect(added.last.mealId, 'thali');
    expect(added.last.quantity, 1);
    expect(added.last.timeSlot, '1:00 PM');
    expect(added.last.id, isNot('host-line'));

    final saved = mergeSharedCartItems(
      remote: [hostLine],
      local: added,
      userId: 'arushi',
      hostId: 'kiranag',
    );
    expect(saved.map((item) => item.addedByUserId).toList(), ['kiranag', 'arushi']);
    expect(saved.first.quantity, 1);
    expect(saved.last.quantity, 1);
  });

  test('a second guest add of the same plate increments only the guest line', () {
    final hostLine = _plate(id: 'host-line', mealId: 'thali', ownerId: 'kiranag', ownerName: 'Kiranag');
    final once = addOwnedGroupPlate(
      items: [hostLine],
      plate: _plate(id: 'incoming', mealId: 'thali', ownerId: 'arushi'),
      userId: 'arushi',
      userName: 'Arushi',
      hostId: 'kiranag',
      roomTimeSlot: '1:00 PM',
    );
    final twice = addOwnedGroupPlate(
      items: once,
      plate: _plate(id: 'incoming-2', mealId: 'thali', ownerId: 'arushi'),
      userId: 'arushi',
      userName: 'Arushi',
      hostId: 'kiranag',
      roomTimeSlot: '1:00 PM',
    );
    expect(twice, hasLength(2));
    expect(twice.first.quantity, 1);
    expect(twice.last.addedByUserId, 'arushi');
    expect(twice.last.quantity, 2);
  });

  test('a guest cannot change the host quantity, extras, time, or place', () {
    final hostLine = _plate(id: 'host-line', mealId: 'thali', ownerId: 'kiranag', ownerName: 'Kiranag');
    final items = [hostLine];

    final quantity = applyOwnedLineEdit(
      items: items,
      lineId: 'host-line',
      userId: 'arushi',
      hostId: 'kiranag',
      quantity: 4,
    );
    expect(quantity.single.quantity, 1);
    expect(quantity.single.addedByUserId, 'kiranag');

    final extras = applyOwnedLineEdit(
      items: items,
      lineId: 'host-line',
      userId: 'arushi',
      hostId: 'kiranag',
      addOns: const [salad],
    );
    expect(extras.single.selectedAddOns, isEmpty);

    final removed = applyOwnedLineEdit(
      items: items,
      lineId: 'host-line',
      userId: 'arushi',
      hostId: 'kiranag',
      remove: true,
    );
    expect(removed.single.id, 'host-line');

    final place = authorizeSharedRoomPatch(
      userId: 'arushi',
      hostId: 'kiranag',
      patch: const SharedRoomPatch(
        placeLabel: 'Somewhere else',
        dropoffNote: 'Other gate',
        timeSlot: '9:00 PM',
        selectedDate: null,
      ),
    );
    expect(place, isNull);
    expect(hostLine.timeSlot, '1:00 PM');
  });

  test('the host can change the shared time and place and a member cannot', () {
    final hostLine = _plate(id: 'host-line', mealId: 'thali', ownerId: 'kiranag', ownerName: 'Kiranag');
    final guestLine = _plate(id: 'guest-line', mealId: 'thali', ownerId: 'arushi', ownerName: 'Arushi');
    final items = [hostLine, guestLine];
    final nextDate = DateTime.utc(2026, 10, 4);

    final guestPatch = authorizeSharedRoomPatch(
      userId: 'arushi',
      hostId: 'kiranag',
      patch: SharedRoomPatch(placeLabel: 'Other desk', timeSlot: '9:00 PM', selectedDate: nextDate),
    );
    expect(guestPatch, isNull);

    final hostPatch = authorizeSharedRoomPatch(
      userId: 'kiranag',
      hostId: 'kiranag',
      patch: SharedRoomPatch(
        placeKind: 'office',
        placeLabel: 'DeskBay3',
        dropoffNote: 'Reception',
        timeSlot: '2:00 PM',
        selectedDate: nextDate,
      ),
    );
    expect(hostPatch, isNotNull);
    expect(hostPatch!.placeLabel, 'DeskBay3');
    expect(hostPatch.dropoffNote, 'Reception');
    expect(hostPatch.timeSlot, '2:00 PM');

    final plates = applySharedScheduleToPlates(
      items,
      timeSlot: hostPatch.timeSlot,
      selectedDate: hostPatch.selectedDate,
    );
    expect(plates, hasLength(2));
    expect(plates.every((item) => item.timeSlot == '2:00 PM'), isTrue);
    expect(plates.every((item) => item.scheduledDate == nextDate), isTrue);
    expect(plates.map((item) => item.addedByUserId).toList(), ['kiranag', 'arushi']);
    expect(plates.map((item) => item.quantity).toList(), [1, 1]);
  });
}
