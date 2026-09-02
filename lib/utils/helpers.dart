// lib/utils/helpers.dart

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

// Export the theme so all screens automatically inherit it
export 'app_theme.dart'; 

class Validators {
  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    // RFC 5822 compliant standard email regex
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(v.trim()) ? null : 'Enter a valid email address';
  }

  static String? password(String? v) {
    if (v == null || v.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  static String? requiredField(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    return null;
  }

  static String? pinCode(String? v) {
    if (v == null || v.trim().length != 6) return 'Enter a valid 6-digit PIN code';
    return null;
  }
}

class Formatters {
  static String currency(double value, {String symbol = '₹'}) {
    final f = NumberFormat.currency(locale: 'en_IN', symbol: symbol, decimalDigits: 0);
    return f.format(value);
  }

  static String shortDateTime(DateTime dt) {
    return DateFormat('dd MMM, hh:mm a').format(dt);
  }
}

class Ui {
  static Widget loadingIndicator({double size = 20}) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

// ----------------------------------------------------------------------
// GLOBAL HELPERS FOR ORDERS & SCHEDULING
// ----------------------------------------------------------------------

String mealDisplayTitle(Map<String, dynamic> meal, {String fallback = 'Meal'}) {
  final title = meal['title']?.toString().trim();
  if (title != null && title.isNotEmpty) return title;
  final name = meal['name']?.toString().trim();
  if (name != null && name.isNotEmpty) return name;
  return fallback;
}

String formatOrderId(String? rawOrderId, String fallbackId) {
  if (rawOrderId != null && rawOrderId.isNotEmpty) {
    return rawOrderId.length > 8 ? rawOrderId.substring(0, 8).toUpperCase() : rawOrderId.toUpperCase();
  }
  return fallbackId.length > 8 ? fallbackId.substring(0, 8).toUpperCase() : fallbackId.toUpperCase();
}

DateTime getTrueOrderDateTime(String rawOrderId, String? createdAt) {
  try {
    final parts = rawOrderId.split('-');
    if (parts.length >= 2) {
      final epoch = int.tryParse(parts[1]);
      if (epoch != null && epoch > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(epoch);
      }
    }
  } catch (_) {}

  if (createdAt != null) {
    final parsed = DateTime.tryParse(createdAt);
    if (parsed != null) return parsed.toLocal();
  }
  return DateTime.now();
}

String formatOrderDate(String? isoString) {
  if (isoString == null || isoString.isEmpty) return 'Unknown Time';
  final dt = DateTime.tryParse(isoString);
  if (dt == null) return 'Unknown Time';
  return DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
}

const Map<String, int> _monthAbbrToNumber = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Extracts the time-of-day portion (e.g. "9:04 AM") from a slot string.
String? extractSlotTime(String slot) {
  final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).firstMatch(slot);
  return match?.group(0)?.toUpperCase();
}

/// Attempts to parse an absolute calendar date embedded in a slot string, e.g.
/// "Sun, 16th Aug at 9:04 AM" or "16/08/2026". Returns null when none is found.
/// A missing year is assumed to be [assumedYear].
DateTime? parseSlotDate(String slot, int assumedYear) {
  // Numeric form: dd/MM or dd/MM/yyyy
  final numeric = RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b').firstMatch(slot);
  if (numeric != null) {
    final d = int.tryParse(numeric.group(1)!);
    final mo = int.tryParse(numeric.group(2)!);
    var y = assumedYear;
    if (numeric.group(3) != null) {
      final yy = int.parse(numeric.group(3)!);
      y = yy < 100 ? 2000 + yy : yy;
    }
    if (d != null && mo != null && mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
      return DateTime(y, mo, d);
    }
  }

  // Named form: "16th Aug", "16 August"
  final named =
      RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,})', caseSensitive: false).firstMatch(slot);
  if (named != null) {
    final d = int.tryParse(named.group(1)!);
    final mo = _monthAbbrToNumber[named.group(2)!.toLowerCase().substring(0, 3)];
    if (d != null && mo != null && d >= 1 && d <= 31) {
      return DateTime(assumedYear, mo, d);
    }
  }
  return null;
}

/// Resolves a stored slot string into a stable, valid label anchored to
/// [placedDate].
///
/// Two problems are corrected here so every screen behaves consistently:
///  1. Relative slots ("Today"/"Tomorrow") are captured as literal text at
///     order time and would otherwise keep re-reading as the current day
///     forever — they are rewritten against [placedDate].
///  2. Absolute slots copied from a meal's stale availability window can fall
///     *before* the order was placed (delivery date earlier than order date),
///     which is impossible — such dates are re-anchored to [placedDate].
///
/// If [selectedDateStr] holds a concrete customer-chosen date, it is preferred.
String smartTimeSlot(String? originalSlot, DateTime placedDate, {String? selectedDateStr}) {
  String slot = originalSlot ?? 'ASAP';

  final hasConcreteSelected = selectedDateStr != null &&
      selectedDateStr.isNotEmpty &&
      selectedDateStr.toLowerCase() != 'today' &&
      selectedDateStr.toLowerCase() != 'tomorrow';

  if (hasConcreteSelected) {
    if (slot.toLowerCase().contains('today')) {
      slot = slot.replaceAll(RegExp('today', caseSensitive: false), selectedDateStr);
    } else if (slot.toLowerCase().contains('tomorrow')) {
      slot = slot.replaceAll(RegExp('tomorrow', caseSensitive: false), selectedDateStr);
    } else if (!slot.contains(selectedDateStr)) {
      slot = '$selectedDateStr | $slot';
    }
  } else if (slot.toLowerCase().contains('today')) {
    slot = slot.replaceAll(
        RegExp('today', caseSensitive: false), DateFormat('d MMM').format(placedDate));
  } else if (slot.toLowerCase().contains('tomorrow')) {
    slot = slot.replaceAll(RegExp('tomorrow', caseSensitive: false),
        DateFormat('d MMM').format(placedDate.add(const Duration(days: 1))));
  }

  // Invariant: a delivery slot can never be earlier than the order date.
  final slotDate = parseSlotDate(slot, placedDate.year);
  if (slotDate != null) {
    final placedDay = DateTime(placedDate.year, placedDate.month, placedDate.day);
    final slotDay = DateTime(slotDate.year, slotDate.month, slotDate.day);
    if (slotDay.isBefore(placedDay)) {
      final time = extractSlotTime(slot);
      final dateStr = DateFormat('EEE, d MMM').format(placedDate);
      slot = time != null ? '$dateStr at $time' : dateStr;
    }
  }
  return slot;
}

String formatFriendlyDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  
  final diffDays = target.difference(today).inDays;
  if (diffDays == 0) return 'Today';
  if (diffDays == 1) return 'Tomorrow';
  if (diffDays == -1) return 'Yesterday';
  
  return DateFormat('dd MMM').format(date);
}

DateTime? parseSlotStartTime(String timeSlot, {DateTime? baseDate}) {
  try {
    final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).firstMatch(timeSlot);
    if (match != null) {
      int h = int.parse(match.group(1)!);
      int m = int.parse(match.group(2)!);
      String ampm = match.group(3)!.toUpperCase();
      if (ampm == 'PM' && h != 12) h += 12;
      if (ampm == 'AM' && h == 12) h = 0;
      
      final date = baseDate ?? DateTime.now();
      return DateTime(date.year, date.month, date.day, h, m);
    }
  } catch (_) {}
  return null;
}

bool isMealExpired(String? timeSlot, {DateTime? orderDate}) {
  if (timeSlot == null || timeSlot.isEmpty) return false;
  final startTime = parseSlotStartTime(timeSlot, baseDate: orderDate);
  if (startTime != null) {
    // Meal expires 3 hours after its scheduled start time
    return DateTime.now().isAfter(startTime.add(const Duration(hours: 3)));
  }
  return false;
}

bool isTimeWithinChefBounds(String selectedTime, String chefScheduleStr) {
  if (chefScheduleStr.isEmpty) return true;
  
  final timeRegex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false);
  final matches = timeRegex.allMatches(chefScheduleStr).toList();
  final selectedMatch = timeRegex.firstMatch(selectedTime);

  if (selectedMatch == null) return true;

  int toMins(RegExpMatch m) {
    int h = int.parse(m.group(1)!);
    if (m.group(3)!.toUpperCase() == 'PM' && h != 12) h += 12;
    if (m.group(3)!.toUpperCase() == 'AM' && h == 12) h = 0;
    return h * 60 + int.parse(m.group(2)!);
  }

  int sel = toMins(selectedMatch);

  // Range provided (e.g., "9:00 AM - 5:00 PM")
  if (matches.length >= 2) {
    int start = toMins(matches[0]);
    int end = toMins(matches[1]);
    return sel >= start && sel <= end;
  }
  
  // Open-ended schedule starting from a time (e.g., "9:00 AM onwards")
  if (matches.length == 1) {
    int start = toMins(matches[0]);
    return sel >= start;
  }

  return true;
}

bool isDateWithinChefBounds(String dateStr, String chefScheduleStr) {
  return true;
}

List<DateTime> getValidDatesForChefSchedule(String scheduleStr) {
  List<DateTime> dates = [];
  final now = DateTime.now();
  for (int i = 0; i < 7; i++) {
    dates.add(now.add(Duration(days: i)));
  }
  return dates;
}

bool isSoldOutCheckoutError(Object? error, [Map<String, dynamic>? data]) {
  if (data?['code']?.toString() == 'sold_out') return true;
  final text = '${data?['error'] ?? error}'.toLowerCase();
  return text.contains('sold out') || text.contains('no longer available');
}

String soldOutCheckoutMessage({required bool charged, bool refunded = false}) {
  if (charged && refunded) {
    return 'This meal just sold out. Your payment was refunded and should return in 5–7 business days.';
  }
  if (charged) {
    return 'This meal just sold out after payment. We are issuing a refund.';
  }
  return 'This meal just sold out. Nothing was charged — pick another portion or chef.';
}

String _cleanAddressPart(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return '';
  return text;
}

/// Builds a single-line address from `user_addresses` or a `users` profile row.
String formatSavedAddress(Map<String, dynamic>? data) {
  if (data == null) return '';

  final parts = <String>[
    _cleanAddressPart(data['house_no']),
    _cleanAddressPart(data['street'] ?? data['address_line1'] ?? data['address_line_1']),
    _cleanAddressPart(data['landmark']),
    _cleanAddressPart(data['city']),
    _cleanAddressPart(data['state']),
  ].where((part) => part.isNotEmpty).toList();

  final pin = _cleanAddressPart(data['postal_code'] ?? data['pincode']);
  if (pin.isNotEmpty) {
    if (parts.isEmpty) return pin;
    return '${parts.join(', ')} - $pin';
  }

  if (parts.isNotEmpty) return parts.join(', ');
  return _cleanAddressPart(data['address'] ?? data['full_address'] ?? data['formatted_address']);
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

Map<String, dynamic>? preferredCheckoutAddress(
  List<Map<String, dynamic>> addresses, {
  Object? selectedId,
}) {
  if (addresses.isEmpty) return null;
  if (selectedId != null) {
    for (final address in addresses) {
      if (address['id'] == selectedId) return address;
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