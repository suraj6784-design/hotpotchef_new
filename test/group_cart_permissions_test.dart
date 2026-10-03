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
  DateTime? scheduledDate,
  List<CartItemAddOn> addOns = const [],
}) {
  return CartItemModel(
    id: id,
    mealId: mealId,
    chefId: 'chef',
    title: 'Veg Jumbo Thali',
    basePrice: 180,
    quantity: quantity,
    scheduledDate: scheduledDate ?? DateTime.utc(2026, 10, 3),
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

  test('a guest add keeps the room time and date already on the plates', () {
    const roomSlot = '3:00 AM to 4:00 AM';
    const mealSlot = '4:00 AM to 5:00 AM';
    final roomDate = DateTime.utc(2026, 10, 3);
    final mealDate = DateTime.utc(2026, 10, 4);
    final hostLine = _plate(
      id: 'host-line',
      mealId: 'thali',
      ownerId: 'kiranag',
      ownerName: 'Kiranag',
      timeSlot: roomSlot,
      scheduledDate: roomDate,
    );
    final saladLine = _plate(
      id: 'salad-line',
      mealId: 'thali',
      ownerId: 'arushi',
      ownerName: 'Arushi',
      timeSlot: roomSlot,
      scheduledDate: roomDate,
      addOns: const [salad],
    );

    final added = addOwnedGroupPlate(
      items: [hostLine, saladLine],
      plate: _plate(
        id: 'incoming',
        mealId: 'thali',
        ownerId: 'kiranag',
        timeSlot: mealSlot,
        scheduledDate: mealDate,
        quantity: 1,
      ),
      userId: 'arushi',
      userName: 'Arushi',
      hostId: 'kiranag',
    );

    expect(added, hasLength(3));
    expect(added[0], hostLine);
    expect(added[1], saladLine);
    expect(added[2].addedByUserId, 'arushi');
    expect(added[2].addedByName, 'Arushi');
    expect(added[2].selectedAddOns, isEmpty);
    expect(added[2].quantity, 1);
    expect(added[2].timeSlot, roomSlot);
    expect(added[2].scheduledDate, roomDate);
    expect(added[2].rawMealDetails['exact_time'], roomSlot);
    expect(added[2].id, isNot('host-line'));
    expect(added[2].id, isNot('salad-line'));

    final again = addOwnedGroupPlate(
      items: added,
      plate: _plate(
        id: 'incoming-2',
        mealId: 'thali',
        ownerId: 'arushi',
        timeSlot: mealSlot,
        scheduledDate: mealDate,
      ),
      userId: 'arushi',
      userName: 'Arushi',
      hostId: 'kiranag',
      roomTimeSlot: '   ',
    );
    expect(again, hasLength(3));
    expect(again[0], hostLine);
    expect(again[1], saladLine);
    expect(again[2].quantity, 2);
    expect(again[2].timeSlot, roomSlot);
    expect(again[2].scheduledDate, roomDate);

    expect(
      authorizeSharedRoomPatch(
        userId: 'arushi',
        hostId: 'kiranag',
        patch: const SharedRoomPatch(
          placeLabel: 'Somewhere else',
          timeSlot: mealSlot,
        ),
      ),
      isNull,
    );
  });

  test('a guest add uses another plate clock when the host line has none', () {
    const roomSlot = '3:00 AM to 4:00 AM';
    final hostLine = _plate(
      id: 'host-line',
      mealId: 'thali',
      ownerId: 'kiranag',
      ownerName: 'Kiranag',
      timeSlot: null,
    );
    final earlier = _plate(
      id: 'salad-line',
      mealId: 'salad',
      ownerId: 'arushi',
      ownerName: 'Arushi',
      timeSlot: roomSlot,
    );
    final added = addOwnedGroupPlate(
      items: [hostLine, earlier],
      plate: _plate(
        id: 'incoming',
        mealId: 'thali',
        ownerId: 'arushi',
        timeSlot: '4:00 AM to 5:00 AM',
      ),
      userId: 'arushi',
      userName: 'Arushi',
      hostId: 'kiranag',
    );
    expect(added[0].timeSlot, isNull);
    expect(added[1].timeSlot, roomSlot);
    expect(added[2].timeSlot, roomSlot);
    expect(added[2].addedByUserId, 'arushi');
    expect(added[0].quantity, 1);
  });

  test('the first plate in an empty room keeps the meal slot', () {
    final added = addOwnedGroupPlate(
      items: const [],
      plate: _plate(
        id: 'incoming',
        mealId: 'thali',
        ownerId: 'kiranag',
        timeSlot: '4:00 AM to 5:00 AM',
      ),
      userId: 'kiranag',
      userName: 'Kiranag',
      hostId: 'kiranag',
    );
    expect(added, hasLength(1));
    expect(added.single.timeSlot, '4:00 AM to 5:00 AM');
    expect(added.single.addedByUserId, 'kiranag');
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
