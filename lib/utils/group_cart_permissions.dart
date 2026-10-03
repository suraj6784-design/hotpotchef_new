import 'package:flutter/foundation.dart';

import '../models/cart_enums.dart';
import '../models/cart_state.dart';

/// A group plate can be changed only by the diner who added it.
/// Older plates with no owner stay with the host.
bool sharedCartLineEditable(
  CartItemModel item, {
  required String? userId,
  required String? hostId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  final owner = item.addedByUserId?.trim() ?? '';
  if (owner.isNotEmpty) return owner == uid;
  final host = hostId?.trim() ?? '';
  return host.isNotEmpty && host == uid;
}

/// Only the diner who started the room can change its time and place.
bool isSharedCartHost({
  required String? userId,
  required String? hostId,
}) {
  final uid = userId?.trim() ?? '';
  final host = hostId?.trim() ?? '';
  return uid.isNotEmpty && host.isNotEmpty && uid == host;
}

/// Time, place, and drop note the host may write onto the room.
class SharedRoomPatch {
  final String? placeKind;
  final String? placeLabel;
  final String? dropoffNote;
  final String? timeSlot;
  final DateTime? selectedDate;

  const SharedRoomPatch({
    this.placeKind,
    this.placeLabel,
    this.dropoffNote,
    this.timeSlot,
    this.selectedDate,
  });
}

/// Host edits are returned as-is. A member's edit is refused.
SharedRoomPatch? authorizeSharedRoomPatch({
  required String? userId,
  required String? hostId,
  required SharedRoomPatch patch,
}) {
  if (!isSharedCartHost(userId: userId, hostId: hostId)) return null;
  return patch;
}

/// Copies the room clock onto every plate so a personal slot cannot diverge.
List<CartItemModel> applySharedScheduleToPlates(
  List<CartItemModel> items, {
  String? timeSlot,
  DateTime? selectedDate,
}) {
  final slot = timeSlot?.trim() ?? '';
  if (slot.isEmpty && selectedDate == null) return List<CartItemModel>.of(items);
  return [
    for (final item in items)
      stampSharedSchedule(item, timeSlot: slot.isEmpty ? null : slot, selectedDate: selectedDate),
  ];
}

CartItemModel stampSharedSchedule(
  CartItemModel item, {
  String? timeSlot,
  DateTime? selectedDate,
}) {
  final slot = timeSlot?.trim() ?? '';
  if (slot.isEmpty && selectedDate == null) return item;
  final raw = Map<String, dynamic>.from(item.rawMealDetails);
  if (slot.isNotEmpty) raw['exact_time'] = slot;
  if (selectedDate != null) {
    final iso = selectedDate.toIso8601String();
    raw['selected_date'] = iso;
    raw['selectedDate'] = iso;
  }
  return item.copyWith(
    timeSlot: slot.isNotEmpty ? slot : item.timeSlot,
    scheduledDate: selectedDate ?? item.scheduledDate,
    rawMealDetails: raw,
  );
}

bool _sameMealAndAddOns(CartItemModel item, CartItemModel plate) {
  return item.mealId == plate.mealId && listEquals(item.selectedAddOns, plate.selectedAddOns);
}

String _freshLineId(List<CartItemModel> items, String mealId, String userId) {
  final base = '${mealId}_${userId}_${DateTime.now().microsecondsSinceEpoch}';
  if (items.every((item) => item.id != base)) return base;
  return '${base}_${items.length}';
}

/// Adds [plate] for [userId]. A matching meal is incremented only when this diner owns that line.
///
/// The host's plate is never reused, even when the meal id and add-ons match.
/// A room slot or date, when set, replaces any slot carried in from the meal.
List<CartItemModel> addOwnedGroupPlate({
  required List<CartItemModel> items,
  required CartItemModel plate,
  required String userId,
  required String? hostId,
  String? userName,
  String? roomTimeSlot,
  DateTime? roomDate,
}) {
  final uid = userId.trim();
  final owned = stampSharedSchedule(
    plate.copyWith(
      addedByUserId: uid,
      addedByName: (userName ?? plate.addedByName)?.trim(),
    ),
    timeSlot: roomTimeSlot,
    selectedDate: roomDate,
  );
  final index = items.indexWhere(
    (item) =>
        _sameMealAndAddOns(item, owned) &&
        sharedCartLineEditable(item, userId: uid, hostId: hostId),
  );
  if (index >= 0) {
    final next = List<CartItemModel>.of(items);
    final existing = next[index];
    next[index] = stampSharedSchedule(
      existing.copyWith(quantity: existing.quantity + owned.quantity),
      timeSlot: roomTimeSlot,
      selectedDate: roomDate,
    );
    return next;
  }
  return [
    ...items,
    owned.copyWith(id: _freshLineId(items, owned.mealId, uid)),
  ];
}

/// Quantity, extras, and removal apply only to a line this diner owns.
List<CartItemModel> applyOwnedLineEdit({
  required List<CartItemModel> items,
  required String lineId,
  required String? userId,
  required String? hostId,
  int? quantity,
  List<CartItemAddOn>? addOns,
  bool remove = false,
}) {
  final index = items.indexWhere((item) => item.id == lineId);
  if (index < 0) return List<CartItemModel>.of(items);
  if (!sharedCartLineEditable(items[index], userId: userId, hostId: hostId)) {
    return List<CartItemModel>.of(items);
  }
  final next = List<CartItemModel>.of(items);
  if (remove || (quantity != null && quantity <= 0)) {
    next.removeAt(index);
    return next;
  }
  var item = next[index];
  if (quantity != null) item = item.copyWith(quantity: quantity);
  if (addOns != null) item = item.copyWith(selectedAddOns: addOns);
  next[index] = item;
  return next;
}
