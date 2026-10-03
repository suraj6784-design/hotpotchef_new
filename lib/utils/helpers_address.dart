part of 'helpers.dart';

String _cleanAddressPart(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return '';
  return text;
}

String normalizeAddressKey(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

bool _addressAlreadyContains(List<String> kept, String part) {
  final needle = normalizeAddressKey(part);
  if (needle.isEmpty) return true;
  final haystack = normalizeAddressKey(kept.join(' '));
  return haystack.contains(needle);
}

/// Builds a single-line address from `user_addresses` or a `users` profile row.
/// City, state, and pin are omitted when they are already present in street/house.
String formatSavedAddress(Map<String, dynamic>? data) {
  if (data == null) return '';

  final parts = <String>[];
  for (final value in [
    data['house_no'] ?? data['flat_no'],
    data['wing'],
    data['society_name'],
    data['street'] ?? data['address_line1'] ?? data['address_line_1'],
    data['landmark'],
    data['city'],
    data['state'],
  ]) {
    final part = _cleanAddressPart(value);
    if (part.isEmpty || _addressAlreadyContains(parts, part)) continue;
    parts.add(part);
  }

  final pin = _cleanAddressPart(data['postal_code'] ?? data['pincode']);
  if (parts.isEmpty) {
    final fallback = _cleanAddressPart(data['address'] ?? data['full_address'] ?? data['formatted_address']);
    if (fallback.isEmpty) return pin;
    if (pin.isNotEmpty && !normalizeAddressKey(fallback).contains(normalizeAddressKey(pin))) {
      return '$fallback - $pin';
    }
    return fallback;
  }

  if (pin.isNotEmpty && !_addressAlreadyContains(parts, pin)) {
    return '${parts.join(', ')} - $pin';
  }
  return parts.join(', ');
}

const _placeholderDropoffLabels = {
  'unknown location',
  'unknown address',
  'kitchen location',
};

String? _explicitDropoff(dynamic value) {
  final text = _cleanAddressPart(value);
  if (text.isEmpty) return null;
  if (_placeholderDropoffLabels.contains(text.toLowerCase())) return null;
  return text;
}

/// Drop-off text for a delivery order.
/// Prefers `delivery_address`, then structured address fields, then a saved-address fallback.
String orderDropoffAddress(
  Map<String, dynamic>? order, {
  Iterable<Map<String, dynamic>> items = const [],
  Map<String, dynamic>? fallbackAddress,
}) {
  final sources = <Map<String, dynamic>>[
    if (order != null) order,
    ...items,
  ];
  for (final source in sources) {
    final explicit = _explicitDropoff(source['delivery_address'] ?? source['dropoff_address']);
    if (explicit != null) return explicit;
  }
  for (final source in sources) {
    final structured = formatSavedAddress({
      'house_no': source['house_no'],
      'street': source['street'],
      'address_line1': source['address_line1'],
      'landmark': source['landmark'],
      'city': source['city'],
      'state': source['state'],
      'postal_code': source['postal_code'],
      'pincode': source['pincode'],
    });
    if (structured.isNotEmpty) return structured;
  }
  if (fallbackAddress != null) {
    final formatted = formatSavedAddress(fallbackAddress);
    if (formatted.isNotEmpty) return formatted;
  }
  return '';
}

/// Kitchen address for pickup or dine-in orders.
String orderPickupAddress(
  Map<String, dynamic>? order, {
  Iterable<Map<String, dynamic>> items = const [],
}) {
  for (final source in [...items, if (order != null) order]) {
    final explicit = _explicitDropoff(
      source['hosting_address'] ?? source['chef_address'] ?? source['kitchen_address'] ?? source['pickup_address'],
    );
    if (explicit != null) return explicit;
  }
  return '';
}

DateTime _addressTimestamp(Map<String, dynamic> address) {
  return DateTime.tryParse(_cleanAddressPart(address['updated_at'] ?? address['created_at'])) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// Drops duplicate saved-address rows (same id, or the same visible address).
List<Map<String, dynamic>> uniqueSavedAddresses(Iterable<Map<String, dynamic>> addresses) {
  final rows = addresses.map((row) => Map<String, dynamic>.from(row)).toList();
  rows.sort((a, b) {
    final aDefault = a['is_default'] == true ? 0 : 1;
    final bDefault = b['is_default'] == true ? 0 : 1;
    if (aDefault != bDefault) return aDefault - bDefault;
    return _addressTimestamp(b).compareTo(_addressTimestamp(a));
  });

  final seenIds = <String>{};
  final seenKeys = <String>{};
  final unique = <Map<String, dynamic>>[];
  for (final row in rows) {
    final id = row['id']?.toString() ?? '';
    if (id.isNotEmpty && !seenIds.add(id)) continue;
    var key = normalizeAddressKey(formatSavedAddress(row));
    if (key.isEmpty) {
      key = [
        addressCoordinate(row, latitude: true)?.toStringAsFixed(5) ?? '',
        addressCoordinate(row, latitude: false)?.toStringAsFixed(5) ?? '',
      ].join(',');
    }
    if (key.isEmpty || key == ',') continue;
    if (!seenKeys.add(key)) continue;
    unique.add(row);
  }
  return unique;
}

/// First saved address, or any save when none is already default, becomes the default drop-off.
bool shouldMarkSavedAddressDefault(
  Iterable<Map<String, dynamic>> existing, {
  Object? editingId,
}) {
  final rows = existing.toList();
  if (rows.isEmpty) return true;
  final hasDefault = rows.any((row) {
    if (editingId != null && row['id']?.toString() == editingId.toString()) return false;
    return row['is_default'] == true;
  });
  return !hasDefault;
}

String? matchingSavedAddressId(
  Iterable<Map<String, dynamic>> existing,
  Map<String, dynamic> candidate,
) {
  final candidateKey = normalizeAddressKey(formatSavedAddress(candidate));
  final candLat = addressCoordinate(candidate, latitude: true);
  final candLng = addressCoordinate(candidate, latitude: false);
  for (final row in existing) {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) continue;
    if (id == candidate['id']?.toString()) continue;
    final key = normalizeAddressKey(formatSavedAddress(row));
    if (candidateKey.isNotEmpty && key == candidateKey) return id;
    final lat = addressCoordinate(row, latitude: true);
    final lng = addressCoordinate(row, latitude: false);
    if (candLat == null || candLng == null || lat == null || lng == null) continue;
    if ((candLat - lat).abs() < 0.00015 && (candLng - lng).abs() < 0.00015) return id;
  }
  return null;
}

double? addressCoordinate(Map<String, dynamic>? data, {required bool latitude}) {
  if (data == null) return null;
  final keys = latitude ? const ['latitude', 'lat'] : const ['longitude', 'lng', 'long'];
  for (final key in keys) {
    final parsed = double.tryParse(data[key]?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

double? kitchenCoordinate(Map<String, dynamic>? data, {required bool latitude}) {
  if (data == null) return null;
  final keys = latitude
      ? const ['pickup_lat', 'kitchen_lat', 'chef_lat', 'latitude', 'lat']
      : const ['pickup_lng', 'kitchen_lng', 'chef_lng', 'longitude', 'lng', 'long'];
  for (final key in keys) {
    final parsed = double.tryParse(data[key]?.toString() ?? '');
    if (parsed != null && parsed != 0) return parsed;
  }
  return null;
}

bool hasKitchenPin(Map<String, dynamic>? data) {
  return kitchenCoordinate(data, latitude: true) != null &&
      kitchenCoordinate(data, latitude: false) != null;
}

/// Soft-warn when a society-night label does not match the group place / address.
String? societyNightAddressMismatchWarning({
  required Iterable<Map<String, dynamic>> cartItems,
  String? sharedPlaceLabel,
  String? deliveryAddress,
}) {
  String? nightLabel;
  for (final item in cartItems) {
    final nested = item['rawMealDetails'] ?? item['mealDetails'] ?? item['meal_details'];
    final merged = {
      if (nested is Map) ...Map<String, dynamic>.from(nested),
      ...item,
    };
    if (!isSocietyNight(merged)) continue;
    final label = societyNightLabel(merged).trim();
    if (label.isNotEmpty && label.toLowerCase() != 'society night') {
      nightLabel = label;
      break;
    }
  }
  if (nightLabel == null) return null;

  final haystack = '${sharedPlaceLabel ?? ''} ${deliveryAddress ?? ''}'.toLowerCase();
  if (haystack.trim().isEmpty) return null;
  final needle = nightLabel.toLowerCase();
  if (haystack.contains(needle)) return null;
  return 'This society night is for $nightLabel — check that your drop matches that building.';
}

bool isEphemeralDeliveryPin(Map<String, dynamic>? address) {
  if (address == null) return false;
  final id = address['id']?.toString() ?? '';
  return id == 'device-location' || address['is_device_location'] == true;
}

Map<String, dynamic>? preferredCheckoutAddress(
  List<Map<String, dynamic>> addresses, {
  Object? selectedId,
  Map<String, dynamic>? hint,
}) {
  final selected = selectedId?.toString();
  final pinHint = isEphemeralDeliveryPin(hint) ? Map<String, dynamic>.from(hint!) : null;
  if (pinHint != null &&
      (selected == null || selected == 'device-location' || selected == pinHint['id']?.toString())) {
    return pinHint;
  }
  if (selected == 'device-location') {
    return pinHint;
  }

  if (addresses.isEmpty) return pinHint;
  if (selected != null && selected.isNotEmpty && selected != 'device-location') {
    for (final address in addresses) {
      if (address['id']?.toString() == selected) return address;
    }
  }
  if (hint != null && !isEphemeralDeliveryPin(hint)) {
    final matchId = matchingSavedAddressId(addresses, hint);
    if (matchId != null) {
      for (final address in addresses) {
        if (address['id']?.toString() == matchId) return address;
      }
    }
    final hintKey = normalizeAddressKey(formatSavedAddress(hint));
    if (hintKey.isNotEmpty) {
      for (final address in addresses) {
        if (normalizeAddressKey(formatSavedAddress(address)) == hintKey) return address;
      }
    }
  }
  for (final address in addresses) {
    if (address['is_default'] == true) return address;
  }

  final ranked = [...addresses];
  ranked.sort((a, b) {
    final aTime = DateTime.tryParse(_cleanAddressPart(a['updated_at'] ?? a['created_at'])) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = DateTime.tryParse(_cleanAddressPart(b['updated_at'] ?? b['created_at'])) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return bTime.compareTo(aTime);
  });
  return ranked.first;
}

Map<String, dynamic>? checkoutAddressFromUserProfile(Map<String, dynamic>? user) {
  if (user == null) return null;
  final formatted = formatSavedAddress(user);
  if (formatted.isEmpty) return null;
  return {
    'id': 'profile',
    'house_no': user['house_no'],
    'street': user['street'] ?? user['address'],
    'city': user['city'],
    'state': user['state'],
    'postal_code': user['postal_code'] ?? user['pincode'],
    'latitude': user['latitude'] ?? user['lat'],
    'longitude': user['longitude'] ?? user['lng'],
    'address': user['address'],
  };
}
