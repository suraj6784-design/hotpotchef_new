part of 'helpers.dart';

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
/// "Sun, 16th Aug at 9:04 AM", "16/08/2026", or "06 Sep 2026".
/// A missing year is assumed to be [assumedYear].
DateTime? parseSlotDate(String slot, int assumedYear) {
  final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(slot);
  if (iso != null) {
    final y = int.tryParse(iso.group(1)!);
    final mo = int.tryParse(iso.group(2)!);
    final d = int.tryParse(iso.group(3)!);
    if (y != null && mo != null && d != null && mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
      return DateTime(y, mo, d);
    }
  }

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

  // Named form: "16th Aug", "06 Sep 2026", "16 August"
  final named = RegExp(
    r'\b(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,})(?:\s+(\d{4}))?',
    caseSensitive: false,
  ).firstMatch(slot);
  if (named != null) {
    final d = int.tryParse(named.group(1)!);
    final monthToken = named.group(2)!.toLowerCase();
    if (monthToken.length >= 3) {
      final mo = _monthAbbrToNumber[monthToken.substring(0, 3)];
      final y = int.tryParse(named.group(3) ?? '') ?? assumedYear;
      if (d != null && mo != null && d >= 1 && d <= 31) {
        return DateTime(y, mo, d);
      }
    }
  }
  return null;
}

/// Parses ISO, `yyyy-MM-dd`, `dd/MM/yyyy`, `dd MMM yyyy`, Today, or Tomorrow.
DateTime? parseFlexibleDate(
  String? raw, {
  int? assumedYear,
  DateTime? placedDate,
}) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  final base = placedDate ?? DateTime.now();
  if (lower == 'today') return DateTime(base.year, base.month, base.day);
  if (lower == 'tomorrow') {
    final next = base.add(const Duration(days: 1));
    return DateTime(next.year, next.month, next.day);
  }

  final iso = DateTime.tryParse(text);
  if (iso != null) return iso.toLocal();

  return parseSlotDate(text, assumedYear ?? base.year);
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

  final placedDay = DateTime(placedDate.year, placedDate.month, placedDate.day);
  DateTime? slotDay = parseFlexibleDate(
    selectedDateStr,
    assumedYear: placedDate.year,
    placedDate: placedDate,
  );

  final lower = slot.toLowerCase();
  if (slotDay == null) {
    if (lower.contains('today')) {
      slotDay = placedDay;
    } else if (lower.contains('tomorrow')) {
      slotDay = placedDay.add(const Duration(days: 1));
    } else {
      slotDay = parseFlexibleDate(slot, assumedYear: placedDate.year, placedDate: placedDate);
    }
  }

  if (slotDay != null) {
    final dayOnly = DateTime(slotDay.year, slotDay.month, slotDay.day);
    if (dayOnly.isBefore(placedDay)) slotDay = placedDay;
  }

  final clock = extractSlotTime(slot);
  final asap = isImmediateDeliverySlot(slot) && clock == null;
  if (asap && slotDay == null) return 'ASAP';
  if (asap && slotDay != null) return '${formatAppDate(slotDay)}, ASAP';
  if (slotDay != null && clock != null) {
    var at = parseClockOnDate(clock, slotDay);
    if (at != null && !at.isAfter(placedDate)) {
      at = at.add(const Duration(days: 1));
    }
    return at != null ? formatAppDateTime(at) : '${formatAppDate(slotDay)}, $clock';
  }
  if (slotDay != null) return formatAppDate(slotDay);
  if (clock != null) {
    final at = parseClockOnDate(clock, placedDate);
    return at != null ? formatAppDateTime(at) : '${formatAppDate(placedDate)}, $clock';
  }
  return slot;
}

String formatFriendlyDate(DateTime date, {DateTime? now}) => formatAppDate(date);

DateTime calendarDay(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Always persist a calendar day with year (`yyyy-MM-dd`) plus `selected_year`.
Map<String, dynamic> storedSlotDateFields(
  Map<String, dynamic> item, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final yearHint = int.tryParse(item['selected_year']?.toString() ?? '');
  final raw = item['selected_date'] ??
      item['selectedDate'] ??
      item['scheduled_date'] ??
      item['scheduledDate'];
  final parsed = parseFlexibleDate(
        raw?.toString(),
        assumedYear: yearHint ?? current.year,
        placedDate: current,
      ) ??
      current;
  final day = calendarDay(parsed);
  return {
    'selected_date': formatAppDateKey(day),
    'scheduled_date': formatAppDateKey(day),
    'selected_year': day.year,
  };
}

DateTime tomorrowCalendarDay({DateTime? now}) {
  return calendarDay(now ?? DateTime.now()).add(const Duration(days: 1));
}

String formatMinutesAsClock(int totalMinutes) {
  final mins = ((totalMinutes % (24 * 60)) + (24 * 60)) % (24 * 60);
  var hour = mins ~/ 60;
  final minute = mins % 60;
  final ampm = hour >= 12 ? 'PM' : 'AM';
  var hour12 = hour % 12;
  if (hour12 == 0) hour12 = 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $ampm';
}

int? clockTextToMinutes(String timeText) {
  final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).firstMatch(timeText);
  if (match == null) return null;
  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final ampm = match.group(3)!.toUpperCase();
  if (ampm == 'PM' && hour != 12) hour += 12;
  if (ampm == 'AM' && hour == 12) hour = 0;
  return hour * 60 + minute;
}

String _chefScheduleTimeRange(String rawChefSlot) {
  var timeRangeStr = rawChefSlot.trim();
  if (timeRangeStr.contains('(') && timeRangeStr.contains(')')) {
    final startIndex = timeRangeStr.indexOf('(');
    final endIndex = timeRangeStr.lastIndexOf(')');
    if (startIndex < endIndex) {
      timeRangeStr = timeRangeStr.substring(startIndex + 1, endIndex).trim();
    }
  }
  return timeRangeStr;
}

/// Hourly bookable windows inside a chef publish string, e.g. `9:00 AM to 5:00 PM`.
List<String> chefHourlySubSlots(String rawChefSlot, {int intervalMinutes = 60}) {
  final timeRangeStr = _chefScheduleTimeRange(rawChefSlot);
  if (!timeRangeStr.toLowerCase().contains('to')) {
    return timeRangeStr.isEmpty ? const [] : [timeRangeStr];
  }

  final parts = timeRangeStr.split(RegExp('to', caseSensitive: false));
  if (parts.length < 2) return [timeRangeStr];

  final startMins = clockTextToMinutes(parts[0].trim());
  final endMinsRaw = clockTextToMinutes(parts[1].trim());
  if (startMins == null || endMinsRaw == null) return [timeRangeStr];

  var endMins = endMinsRaw;
  if (endMins <= startMins) endMins += 24 * 60;

  final generated = <String>[];
  var current = startMins;
  final step = intervalMinutes < 15 ? 15 : intervalMinutes;
  while (current + step <= endMins) {
    final next = current + step;
    generated.add('${formatMinutesAsClock(current)} to ${formatMinutesAsClock(next)}');
    current = next;
  }
  return generated.isNotEmpty ? generated : [timeRangeStr];
}

final _clockRangePattern = RegExp(
  r'(\d{1,2}:\d{2}\s*(?:AM|PM))\s+to\s+(\d{1,2}:\d{2}\s*(?:AM|PM))',
  caseSensitive: false,
);

/// True when the slot is a kitchen/diner window (`9:00 AM to 11:00 PM`), not a single clock.
bool slotHasClockRange(String? slot) {
  final text = (slot ?? '').trim();
  if (text.isEmpty || isImmediateDeliverySlot(text)) return false;
  return looksLikeChefServingWindow(text) || _clockRangePattern.hasMatch(text);
}

/// Same template as chef cart slots: `9:00 AM to 10:00 AM`.
String chefSlotWindowLabel(String? slot) {
  final text = (slot ?? '').trim();
  if (text.isEmpty || isImmediateDeliverySlot(text)) return 'ASAP';
  final range = _clockRangePattern.firstMatch(text);
  if (range != null) {
    String norm(String raw) {
      final mins = clockTextToMinutes(raw);
      return mins == null ? raw.trim() : formatMinutesAsClock(mins);
    }

    return '${norm(range.group(1)!)} to ${norm(range.group(2)!)}';
  }
  final start = clockTextToMinutes(text);
  if (start != null) {
    return '${formatMinutesAsClock(start)} to ${formatMinutesAsClock(start + 60)}';
  }
  return text;
}

String dayOrdinalSuffix(int day) {
  if (day >= 11 && day <= 13) return 'th';
  switch (day % 10) {
    case 1:
      return 'st';
    case 2:
      return 'nd';
    case 3:
      return 'rd';
    default:
      return 'th';
  }
}

/// Calendar day on promised slots (`dd MMM yyyy`).
String formatPromisedSlotDate(DateTime date) => formatAppDate(date);

String? firstClockInSlot(String? slot) {
  final match = RegExp(r'(\d{1,2}:\d{2}\s*(?:AM|PM))', caseSensitive: false).firstMatch(slot ?? '');
  if (match == null) return null;
  final mins = clockTextToMinutes(match.group(1)!);
  if (mins == null) return match.group(1)!.trim();
  final hour = mins ~/ 60;
  final minute = mins % 60;
  return formatAppTime(DateTime(2026, 1, 1, hour, minute));
}

/// Diner-facing stamp: calendar day + the clock they booked, never a chef range.
String formatDinerSelectedSlotLabel(String? slot, {DateTime? onDate}) {
  final text = (slot ?? '').trim();
  final clock = firstClockInSlot(text);
  if (clock == null || isImmediateDeliverySlot(text)) {
    if (onDate == null) return isImmediateDeliverySlot(text) || text.isEmpty ? 'ASAP' : text;
    return isImmediateDeliverySlot(text) || text.isEmpty
        ? '${formatAppDate(onDate)}, ASAP'
        : '${formatAppDate(onDate)}, $text';
  }
  if (onDate == null) return clock;
  final at = parseClockOnDate(clock, onDate);
  return at != null ? formatAppDateTime(at) : '${formatAppDate(onDate)}, $clock';
}

String dinerSelectedClockLabel(String? slot) {
  final text = (slot ?? '').trim();
  if (text.isEmpty || text.toLowerCase() == 'select slot') return 'Select time';
  if (isImmediateDeliverySlot(text)) return 'Select time';
  if (looksLikeChefServingWindow(text)) return 'Select time';
  return firstClockInSlot(text) ?? text;
}

/// Promised slot copy: `09 Sep 2026, 10:00 AM`.
String formatPromisedSlotWindow(String? slot, {DateTime? onDate}) {
  return formatDinerSelectedSlotLabel(slot, onDate: onDate);
}

/// Customer-chosen hour beats the chef's published serving window.
String preferredDinerTimeSlot(Iterable<dynamic> candidates, {String fallback = 'ASAP'}) {
  String? booked;
  String? serving;
  for (final raw in candidates) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) continue;
    if (isImmediateDeliverySlot(text)) continue;
    if (looksLikeChefServingWindow(text)) {
      serving ??= text;
    } else {
      booked ??= text;
    }
  }
  return booked ?? serving ?? fallback;
}

/// Checkout copy: diner-chosen clock on the scheduled day.
String formatCheckoutDeliverySchedule({
  required String? slot,
  DateTime? scheduledDate,
  DateTime? now,
}) {
  return formatDinerSelectedSlotLabel(slot, onDate: scheduledDate ?? now);
}

/// Compact kitchen window for meal cards (`9:00 AM–10:00 AM`).
String feedKitchenSlotLabel(String? timeSlot) {
  final window = chefSlotWindowLabel(timeSlot);
  if (window == 'ASAP') return 'On your slot';
  return window.replaceAll(' to ', '–');
}

bool isCartSlotPassed(
  String selectedSlot,
  DateTime scheduledDate, {
  DateTime? now,
}) {
  final n = (now ?? DateTime.now()).toLocal();
  final day = calendarDay(scheduledDate);
  final today = calendarDay(n);
  if (day.isBefore(today)) return true;
  if (day.isAfter(today)) return false;
  final start = parseSlotStartTime(selectedSlot, baseDate: day);
  if (start == null) return false;
  return !start.isAfter(n);
}

List<String> futureChefSubSlots(
  String rawChefSlot, {
  required DateTime scheduledDate,
  DateTime? now,
  int intervalMinutes = 60,
}) {
  return chefHourlySubSlots(rawChefSlot, intervalMinutes: intervalMinutes)
      .where((slot) => !isCartSlotPassed(slot, scheduledDate, now: now))
      .toList();
}

/// Selected bookable window must sit inside the chef's published range.
bool isCartSlotWithinChefWindow(String selectedSlot, String chefSchedule) {
  final schedule = chefSchedule.trim();
  if (schedule.isEmpty) return true;
  final selectedStart = clockTextToMinutes(selectedSlot);
  if (selectedStart == null) return isTimeWithinChefBounds(selectedSlot, schedule);

  final range = _chefScheduleTimeRange(schedule);
  final clocks = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).allMatches(range).toList();
  if (clocks.isEmpty) return true;

  int toMins(RegExpMatch m) {
    var h = int.parse(m.group(1)!);
    final ampm = m.group(3)!.toUpperCase();
    if (ampm == 'PM' && h != 12) h += 12;
    if (ampm == 'AM' && h == 12) h = 0;
    return h * 60 + int.parse(m.group(2)!);
  }

  final start = toMins(clocks.first);
  if (clocks.length == 1) return selectedStart >= start;
  var end = toMins(clocks[1]);
  if (end <= start) end += 24 * 60;
  // Allow booking a slot that starts inside the window (end exclusive for next-day wrap).
  return selectedStart >= start && selectedStart < end;
}

String? cartLineSlotValidationError({
  required String? selectedSlot,
  required DateTime scheduledDate,
  required String? chefSchedule,
  DateTime? now,
}) {
  final selected = (selectedSlot ?? '').trim();
  final schedule = (chefSchedule ?? '').trim();
  if (selected.isEmpty || selected.toLowerCase() == 'select slot') {
    return 'Choose a delivery time slot before checkout.';
  }
  if (isImmediateDeliverySlot(selected)) {
    return 'Choose a clock time inside the chef\'s serving window.';
  }
  if (isCartSlotPassed(selected, scheduledDate, now: now)) {
    return 'That time slot has passed. Pick a later slot inside the chef\'s window.';
  }
  if (schedule.isNotEmpty && !chefSlotAllowsDate(schedule, scheduledDate, now: now)) {
    return 'Pick a day inside the chef\'s published slot.';
  }
  if (schedule.isNotEmpty && !isCartSlotWithinChefWindow(selected, schedule)) {
    return 'Choose a time inside the chef\'s published serving window.';
  }
  return null;
}

String? cartItemsSlotValidationError(
  Iterable<Map<String, dynamic>> items, {
  DateTime? now,
}) {
  for (final item in items) {
    final nested = item['rawMealDetails'] ?? item['mealDetails'] ?? item['meal_details'];
    final nestedMap = nested is Map ? Map<String, dynamic>.from(nested) : const <String, dynamic>{};
    final schedule = (nestedMap['time_slot'] ??
            nestedMap['chef_schedule'] ??
            item['chef_schedule'] ??
            item['time_slot'] ??
            '')
        .toString();
    final selected = (item['time_slot'] ??
            item['timeSlot'] ??
            nestedMap['exact_time'] ??
            item['exact_time'] ??
            '')
        .toString();
    final dateRaw = item['selected_date'] ?? item['selectedDate'] ?? item['scheduled_date'];
    final scheduled = dateRaw is DateTime
        ? dateRaw
        : (DateTime.tryParse(dateRaw?.toString() ?? '') ?? (now ?? DateTime.now()));
    final issue = cartLineSlotValidationError(
      selectedSlot: selected,
      scheduledDate: scheduled,
      chefSchedule: schedule,
      now: now,
    );
    if (issue != null) return issue;
  }
  return null;
}

/// First clock from a chef schedule / meal slot string (e.g. "7:30 PM to 8:30 PM").
String? preferredChefSlotClock(String? schedule) {
  final text = (schedule ?? '').trim();
  if (text.isEmpty) return null;
  final match = RegExp(r'(\d{1,2}:\d{2}\s*(?:AM|PM))', caseSensitive: false).firstMatch(text);
  if (match != null) {
    return match.group(1)!.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }
  if (!isImmediateDeliverySlot(text)) return text;
  return null;
}

String _chefSlotDateLabel(DateTime day, DateTime today) {
  final d = calendarDay(day);
  final t = calendarDay(today);
  if (d == t) return 'Today';
  if (d == t.add(const Duration(days: 1))) return 'Tomorrow';
  return formatPromisedSlotDate(d);
}

Map<String, String> _chefSlotScheduleForDay({
  required String text,
  required DateTime day,
  required DateTime now,
  required String time,
}) {
  return {
    'date': _chefSlotDateLabel(day, now),
    'date_iso': calendarDay(day).toIso8601String(),
    'time': time,
  };
}

/// Default cart day/time: next future sub-slot inside the chef window (never a past clock).
Map<String, String> chefSlotDefaultSchedule(String chefScheduleStr, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toLocal();
  final today = calendarDay(current);
  final text = chefScheduleStr.trim();
  final servingDays = chefServingWeekdays(text);
  final pinned = parseSlotCalendarDay(text, now: current);

  if (pinned != null) {
    final day = calendarDay(pinned);
    final future = futureChefSubSlots(text, scheduledDate: day, now: current);
    final hours = chefHourlySubSlots(text);
    final time = future.isNotEmpty
        ? future.first
        : (hours.isNotEmpty ? hours.first : (preferredChefSlotClock(text) ?? text));
    return _chefSlotScheduleForDay(text: text, day: day, now: current, time: time);
  }

  if (servingDays != null && servingDays.isNotEmpty) {
    for (var i = 0; i < 14; i++) {
      final day = today.add(Duration(days: i));
      if (!servingDays.contains(day.weekday)) continue;
      final future = futureChefSubSlots(text, scheduledDate: day, now: current);
      if (future.isNotEmpty) {
        return _chefSlotScheduleForDay(text: text, day: day, now: current, time: future.first);
      }
    }
  }

  final todayFuture = futureChefSubSlots(text, scheduledDate: today, now: current);
  if (todayFuture.isNotEmpty) {
    return _chefSlotScheduleForDay(text: text, day: today, now: current, time: todayFuture.first);
  }

  // Standing Daily / Sat-Sun windows may roll forward. A one-off chef hour does not.
  if (looksLikeChefServingWindow(text) || (servingDays != null && servingDays.isNotEmpty)) {
    for (var i = 1; i < 14; i++) {
      final day = today.add(Duration(days: i));
      if (servingDays != null && servingDays.isNotEmpty && !servingDays.contains(day.weekday)) {
        continue;
      }
      final hours = chefHourlySubSlots(text);
      if (hours.isNotEmpty) {
        return _chefSlotScheduleForDay(text: text, day: day, now: current, time: hours.first);
      }
    }
  }

  final hours = chefHourlySubSlots(text);
  final clock = hours.isNotEmpty ? hours.first : (preferredChefSlotClock(text) ?? text);
  return _chefSlotScheduleForDay(text: text, day: today, now: current, time: clock);
}

DateTime chefSlotDefaultDate(Map<String, String> schedule, {DateTime? now}) {
  final iso = schedule['date_iso']?.trim() ?? '';
  if (iso.isNotEmpty) {
    final parsed = DateTime.tryParse(iso);
    if (parsed != null) return calendarDay(parsed.toLocal());
  }
  final current = (now ?? DateTime.now()).toLocal();
  if (schedule['date'] == 'Tomorrow') return tomorrowCalendarDay(now: current);
  return calendarDay(current);
}

DateTime? parseClockOnDate(String timeText, DateTime date) {
  final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).firstMatch(timeText);
  if (match == null) return null;
  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final ampm = match.group(3)!.toUpperCase();
  if (ampm == 'PM' && hour != 12) hour += 12;
  if (ampm == 'AM' && hour == 12) hour = 0;
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day, hour, minute);
}

DateTime? parseSlotStartTime(String timeSlot, {DateTime? baseDate}) {
  return parseClockOnDate(timeSlot, baseDate ?? DateTime.now());
}

int mealPortionsLeft(Map<String, dynamic> meal) {
  return int.tryParse(meal['quantity']?.toString() ?? '') ?? 0;
}

String mealPortionsLeftLabel(Map<String, dynamic> meal) {
  final left = mealPortionsLeft(meal);
  final status = meal['status']?.toString().toLowerCase().trim() ?? '';
  if (left <= 0 || status == 'sold out') return 'Sold out';
  if (left == 1) return '1 left';
  return '$left left';
}

bool mealHasSellableStock(Map<String, dynamic> meal) {
  final qty = int.tryParse(meal['quantity']?.toString() ?? '0') ?? 0;
  final status = meal['status']?.toString().toLowerCase().trim() ?? '';
  if (qty <= 0) return false;
  if (status == 'sold out' || status == 'paused' || status == 'unavailable') return false;
  return true;
}

bool isMealAvailableForCart(Map<String, dynamic> meal, {DateTime? now}) {
  if (!mealHasSellableStock(meal)) return false;
  if (isChefMealArchived(meal)) return false;
  return !isPublishedMealExpired(meal, now: now);
}

bool isCatalogMeal(Map<String, dynamic> meal) {
  final owner = meal['customer_name']?.toString().trim() ?? '';
  return owner.isEmpty;
}

/// Placeholder leftovers from older publish (₹0, Flexible/ASAP, no pin, no service).
bool mealFailsCurrentCatalogRequirements(Map<String, dynamic> meal) {
  if (isChefMealArchived(meal)) return false;
  final title = meal['title']?.toString().trim() ?? '';
  if (title.isEmpty) return true;
  if (PricingCalculator.basePrice(meal) <= 0) return true;
  if (mealHasPlaceholderOrMissingSlot(meal)) return true;
  if ((meal['service_type'] ?? meal['selected_service_type'] ?? '').toString().trim().isEmpty) {
    return true;
  }
  return false;
}

bool mealHasPlaceholderOrMissingSlot(Map<String, dynamic> meal) {
  final slot = meal['time_slot']?.toString().trim() ?? '';
  if (slot.isEmpty || isImmediateDeliverySlot(slot)) return true;
  return !RegExp(r'\d{1,2}:\d{2}').hasMatch(slot);
}

bool isMealExpired(String? timeSlot, {DateTime? orderDate, DateTime? now}) {
  if (timeSlot == null || timeSlot.isEmpty) return false;
  // Standing weekly kitchens stay preorderable until the chef pauses or archives.
  if (isStandingWeeklyServingWindow(timeSlot)) return false;
  final n = (now ?? DateTime.now()).toLocal();
  final labeledDay = parseSlotCalendarDay(timeSlot, now: n);
  if (orderDate == null && labeledDay != null && calendarDay(labeledDay).isBefore(calendarDay(n))) {
    return true;
  }
  final day = calendarDay(orderDate ?? labeledDay ?? n);
  final clocks = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).allMatches(timeSlot).toList();
  if (clocks.isEmpty) return false;

  DateTime? end;
  if (clocks.length >= 2) {
    end = parseClockOnDate(clocks[1].group(0)!, day);
  } else {
    end = parseClockOnDate(clocks.first.group(0)!, day);
  }
  if (end == null) return false;
  // Catalog stays bookable until the chef window ends — not hours after the start clock.
  return !n.isBefore(end);
}

const _kMonthNames = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Parses a calendar day from labels like "Sun, 18th Aug at 9:30 AM" or chef one-time "2026-09-17 (12:00 PM to 2:00 PM)".
DateTime? parseSlotCalendarDay(String? raw, {DateTime? now}) {
  if (raw == null || raw.trim().isEmpty) return null;
  final n = (now ?? DateTime.now()).toLocal();
  final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(raw);
  if (iso != null) {
    final year = int.tryParse(iso.group(1) ?? '');
    final month = int.tryParse(iso.group(2) ?? '');
    final day = int.tryParse(iso.group(3) ?? '');
    if (year != null && month != null && day != null) {
      return DateTime(year, month, day);
    }
  }
  final match = RegExp(
    r'(\d{1,2})(?:st|nd|rd|th)?\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*(?:\s+(\d{4}))?',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) return null;
  final day = int.tryParse(match.group(1) ?? '');
  final month = _kMonthNames[(match.group(2) ?? '').toLowerCase().substring(0, 3)];
  if (day == null || month == null) return null;
  var year = int.tryParse(match.group(3) ?? '') ?? n.year;
  var parsed = DateTime(year, month, day);
  // If label has no year and the day is far ahead, it was likely last year.
  if (match.group(3) == null && parsed.difference(n).inDays > 180) {
    parsed = DateTime(year - 1, month, day);
  }
  return parsed;
}

bool isChefMealArchived(Map<String, dynamic> meal) {
  final status = meal['status']?.toString().toLowerCase().trim() ?? '';
  return status == 'archived' || status == 'deleted' || status == 'expired';
}

/// True when the dish window is over (for Menu Active vs History).
bool isPublishedMealExpired(Map<String, dynamic> meal, {DateTime? now}) {
  if (isChefMealArchived(meal)) return true;
  final n = now ?? DateTime.now();
  final slot = meal['time_slot']?.toString();
  if (isStandingWeeklyServingWindow(slot)) return false;
  final selected = DateTime.tryParse(meal['selected_date']?.toString() ?? '');
  final labeledDay = parseSlotCalendarDay(slot, now: n);
  final day = selected ?? labeledDay;
  if (day != null && calendarDay(day).isBefore(calendarDay(n))) {
    return true;
  }
  return isMealExpired(slot, orderDate: day, now: n);
}

bool isChefMenuActiveMeal(Map<String, dynamic> meal, {DateTime? now}) {
  if (isChefMealArchived(meal)) return false;
  return !isPublishedMealExpired(meal, now: now);
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

/// Chefs may start cooking once the requested drop-off is this close.
/// Four hours lets kitchens batch earlier without waiting until the last two.
const int kChefPrepEarliestMinutes = 240;

String chefPrepEarliestWindowLabel() {
  final hours = kChefPrepEarliestMinutes / 60.0;
  if (hours == hours.roundToDouble()) {
    final n = hours.toInt();
    return n == 1 ? '1 hour' : '$n hours';
  }
  return '$kChefPrepEarliestMinutes minutes';
}

/// Ideal last-hour cooking window shown on the chef card.
const int kChefPrepIdealMinutes = 60;

bool isImmediateDeliverySlot(String? slot) {
  final text = (slot ?? '').trim().toLowerCase();
  if (text.isEmpty || text == 'asap' || text == 'now' || text == 'flexible') return true;
  if (text.contains('flexible')) return true;
  return text.contains('asap') && !RegExp(r'\d{1,2}:\d{2}').hasMatch(text);
}

int? _slotClockSpanMinutes(String text) {
  final matches = RegExp(r'(\d{1,2}:\d{2}\s*(?:AM|PM))', caseSensitive: false).allMatches(text).toList();
  if (matches.length < 2) return null;
  final start = clockTextToMinutes(matches.first.group(1)!);
  final end = clockTextToMinutes(matches.last.group(1)!);
  if (start == null || end == null) return null;
  var span = end - start;
  if (span <= 0) span += 24 * 60;
  return span;
}

/// Chef serving hours (e.g. "Sat, Sun (9:00 AM to 11:00 PM)"), not a diner hourly clock.
bool looksLikeChefServingWindow(String? slot) {
  final text = (slot ?? '').trim();
  if (text.isEmpty || isImmediateDeliverySlot(text)) return false;
  final lower = text.toLowerCase();
  final namedDays = RegExp(r'\b(daily|weekdays|weekends|mon|tue|wed|thu|fri|sat|sun)\b').hasMatch(lower);
  final clocks = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).allMatches(text).length;
  if (namedDays && clocks >= 1) return true;
  final span = _slotClockSpanMinutes(text);
  // Bookable cart slots are typically one hour ("11:00 AM to 12:00 PM").
  // Kitchen open hours span several hours.
  return span != null && span > 120;
}

/// True when [day] is a calendar day the chef actually published.
bool chefSlotAllowsDate(String chefSchedule, DateTime day, {DateTime? now}) {
  final schedule = chefSchedule.trim();
  if (schedule.isEmpty || isImmediateDeliverySlot(schedule)) return true;
  final n = (now ?? DateTime.now()).toLocal();
  final d = calendarDay(day);
  if (d.isBefore(calendarDay(n))) return false;
  final pinned = parseSlotCalendarDay(schedule, now: n);
  if (pinned != null) return calendarDay(pinned) == d;
  final days = chefServingWeekdays(schedule);
  if (days != null && days.isNotEmpty) return days.contains(d.weekday);
  final lower = schedule.toLowerCase();
  if (RegExp(r'\btoday\b').hasMatch(lower)) return d == calendarDay(n);
  if (RegExp(r'\btomorrow\b').hasMatch(lower)) return d == tomorrowCalendarDay(now: n);
  if (looksLikeChefServingWindow(schedule)) {
    return futureChefSubSlots(schedule, scheduledDate: d, now: n).isNotEmpty || d == calendarDay(n);
  }
  return d == calendarDay(n);
}

DateTime chefSlotPickerFirstDate(String chefSchedule, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toLocal();
  final today = calendarDay(n);
  final pinned = parseSlotCalendarDay(chefSchedule, now: n);
  if (pinned != null) {
    final day = calendarDay(pinned);
    return day.isBefore(today) ? today : day;
  }
  for (var i = 0; i < 15; i++) {
    final day = today.add(Duration(days: i));
    if (chefSlotAllowsDate(chefSchedule, day, now: n)) return day;
  }
  return today;
}

DateTime chefSlotPickerLastDate(String chefSchedule, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toLocal();
  final today = calendarDay(n);
  final pinned = parseSlotCalendarDay(chefSchedule, now: n);
  if (pinned != null) {
    final day = calendarDay(pinned);
    return day.isBefore(today) ? today : day;
  }
  final days = chefServingWeekdays(chefSchedule);
  if (days != null && days.isNotEmpty) return today.add(const Duration(days: 14));
  if (looksLikeChefServingWindow(chefSchedule)) return today.add(const Duration(days: 14));
  return today;
}

DateTime chefSlotPickerInitialDate(String chefSchedule, DateTime scheduled, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (chefSlotAllowsDate(chefSchedule, scheduled, now: n)) return calendarDay(scheduled);
  return chefSlotPickerFirstDate(chefSchedule, now: n);
}

/// Weekdays a standing kitchen window repeats on. Null when the slot is one-off.
Set<int>? chefServingWeekdays(String? slot) {
  final text = (slot ?? '').trim().toLowerCase();
  if (text.isEmpty) return null;
  if (RegExp(r'\bdaily\b').hasMatch(text)) {
    return {1, 2, 3, 4, 5, 6, 7};
  }
  if (RegExp(r'\bweekends?\b').hasMatch(text)) {
    return {DateTime.saturday, DateTime.sunday};
  }
  if (RegExp(r'\bweekdays?\b').hasMatch(text)) {
    return {DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday};
  }
  final days = <int>{};
  const tokens = <String, int>{
    r'mon(?:day)?': DateTime.monday,
    r'tue(?:s(?:day)?)?': DateTime.tuesday,
    r'wed(?:nesday)?': DateTime.wednesday,
    r'thu(?:rs(?:day)?)?': DateTime.thursday,
    r'fri(?:day)?': DateTime.friday,
    r'sat(?:urday)?': DateTime.saturday,
    r'sun(?:day)?': DateTime.sunday,
  };
  for (final entry in tokens.entries) {
    if (RegExp('\\b${entry.key}\\b').hasMatch(text)) days.add(entry.value);
  }
  return days.isEmpty ? null : days;
}

/// Repeating Sat/Sun (or Daily) windows stay on the menu for the next matching day.
bool isStandingWeeklyServingWindow(String? slot) {
  if (parseSlotCalendarDay(slot) != null) return false;
  if (chefServingWeekdays(slot) == null) return false;
  return looksLikeChefServingWindow(slot);
}

Map<String, dynamic> orderSlotFields(Map<String, dynamic> order) {
  final items = parseOrderItemsList(order['items'] ?? order['cart_items'] ?? order['order_items']);
  final first = items.isNotEmpty ? items.first : const <String, dynamic>{};
  final nestedRaw = first['rawMealDetails'] ??
      first['mealDetails'] ??
      first['meal_details'] ??
      order['rawMealDetails'] ??
      order['mealDetails'] ??
      order['meal_details'];
  final nested = nestedRaw is Map ? Map<String, dynamic>.from(nestedRaw) : const <String, dynamic>{};
  final maps = [order, first, nested];

  String pick(List<String> keys, {bool skipAsap = false}) {
    String? asap;
    for (final map in maps) {
      for (final key in keys) {
        final value = map[key];
        if (value == null || value.toString().trim().isEmpty) continue;
        final text = value.toString();
        if (skipAsap && isImmediateDeliverySlot(text)) {
          asap ??= 'ASAP';
          continue;
        }
        return text;
      }
    }
    return asap ?? '';
  }

  String pickTimeSlot() {
    const keys = ['exact_time', 'timeSlot', 'selected_slot', 'delivery_slot', 'time_slot', 'chef_schedule'];
    final candidates = <dynamic>[];
    for (final map in maps) {
      for (final key in keys) {
        candidates.add(map[key]);
      }
    }
    return preferredDinerTimeSlot(candidates, fallback: '');
  }

  return {
    ...order,
    'time_slot': pickTimeSlot(),
    'selected_date': pick(const ['selected_date', 'selectedDate', 'scheduled_date', 'scheduledDate']),
    'selected_year': pick(const ['selected_year']),
  };
}

/// Start of the scheduled slot, used to stop customer cancel once the window begins.
DateTime? orderSlotStart(Map<String, dynamic> order, {DateTime? now}) {
  final fields = orderSlotFields(order);
  final placed = DateTime.tryParse(fields['created_at']?.toString() ?? '')?.toLocal() ?? now;
  final rawSlot = fields['time_slot']?.toString() ?? '';
  if (isImmediateDeliverySlot(rawSlot) && (fields['selected_date']?.toString() ?? '').isEmpty) {
    return null;
  }
  if (rawSlot.isEmpty && placed == null) return null;
  final slot = smartTimeSlot(
    rawSlot.isEmpty ? null : rawSlot,
    placed ?? DateTime.now(),
    selectedDateStr: fields['selected_date']?.toString(),
  );
  if (isImmediateDeliverySlot(slot)) return null;
  final assumedYear = (placed ?? DateTime.now()).year;
  final date = parseSlotDate(slot, assumedYear) ??
      (placed != null ? DateTime(placed.year, placed.month, placed.day) : null);
  if (date == null) return null;
  return parseClockOnDate(slot, date) ?? DateTime(date.year, date.month, date.day);
}

String formatDeliverySlotLabel(Map<String, dynamic> order, {DateTime? now}) {
  final fields = orderSlotFields(order);
  final placed = DateTime.tryParse(fields['created_at']?.toString() ?? '')?.toLocal() ?? now ?? DateTime.now();
  final rawSlot = fields['time_slot']?.toString() ?? '';
  final selectedDateStr = fields['selected_date']?.toString().trim() ?? '';
  final yearHint = int.tryParse(fields['selected_year']?.toString() ?? '');
  if (isImmediateDeliverySlot(rawSlot) && selectedDateStr.isEmpty && yearHint == null) {
    return 'ASAP';
  }
  var slotDay = parseFlexibleDate(
        selectedDateStr.isEmpty ? null : selectedDateStr,
        assumedYear: yearHint ?? placed.year,
        placedDate: placed,
      ) ??
      DateTime(placed.year, placed.month, placed.day);
  if (yearHint != null && yearHint > 2000) {
    slotDay = DateTime(yearHint, slotDay.month, slotDay.day);
  }
  if (slotHasClockRange(rawSlot) || firstClockInSlot(rawSlot) != null) {
    return formatDinerSelectedSlotLabel(rawSlot, onDate: slotDay);
  }
  return smartTimeSlot(
    rawSlot.isEmpty ? 'ASAP' : rawSlot,
    placed,
    selectedDateStr: selectedDateStr.isEmpty ? null : selectedDateStr,
  );
}

/// Start Preparing unlocks [kChefPrepEarliestMinutes] before the requested time,
/// and stays on through the last hour and after the slot (food must still go out).
bool canChefStartPreparing(Map<String, dynamic> order, {DateTime? now}) {
  final start = orderSlotStart(order, now: now);
  if (start == null) return true;
  final current = now ?? DateTime.now();
  return !start.subtract(const Duration(minutes: kChefPrepEarliestMinutes)).isAfter(current);
}

String chefPrepGateHint(Map<String, dynamic> order, {DateTime? now}) {
  if (canChefStartPreparing(order, now: now)) return '';
  final start = orderSlotStart(order, now: now);
  if (start == null) return '';
  final unlockAt = start.subtract(const Duration(minutes: kChefPrepEarliestMinutes));
  final wait = formatSlotCountdown(unlockAt, now: now).replaceAll(' left', '');
  if (wait.isEmpty) {
    return 'Opens ${chefPrepEarliestWindowLabel()} before the requested time';
  }
  return 'Opens in $wait (${chefPrepEarliestWindowLabel()} before requested time)';
}

String _humanDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 1) return 'under a minute';
  if (minutes < 60) return '$minutes min';
  final hours = duration.inHours;
  final rem = minutes % 60;
  if (hours < 24) return rem == 0 ? '$hours hr' : '$hours hr $rem min';
  final days = duration.inDays;
  return days == 1 ? '1 day' : '$days days';
}

bool dinerSlotCountdownActive(String? status) {
  final s = (status ?? '').toLowerCase();
  if (s.contains('cancel') || s.contains('reject')) return false;
  if (s.contains('delivered')) return false;
  if (s.contains('complet') && !s.contains('out')) return false;
  return true;
}

bool dinerSlotIsLate(Map<String, dynamic> order, {DateTime? now}) {
  final promised = orderPromisedAt(order, now: now) ?? orderSlotStart(order, now: now);
  if (promised == null) return false;
  return promised.isBefore(now ?? DateTime.now());
}

/// Diner-facing promised slot, e.g. "Arriving by 08:00 PM · 12 min left"
/// or "Arriving by 18 Sep 2026, 02:00 PM · 1 day left".
String dinerPromisedSlotCopy(Map<String, dynamic> order, {DateTime? now, String? status}) {
  if (!dinerSlotCountdownActive(status ?? order['status']?.toString())) return '';
  final promised = orderPromisedAt(order, now: now);
  final start = promised ?? orderSlotStart(order, now: now);
  final slot = promised != null
      ? formatAppWhen(promised, now: now)
      : formatDeliverySlotLabel(order, now: now);
  final tick = formatSlotCountdown(start, now: now);
  final lateNote = dinerLateOrderCopy(order, now: now);
  String core;
  if (tick.isEmpty) {
    core = slot == 'ASAP' ? 'Arriving ASAP' : 'Arriving by $slot';
  } else if (tick == 'Due now') {
    core = 'Due now · arriving by $slot';
  } else if (tick.contains('late')) {
    core = '$tick · promised $slot';
  } else {
    core = 'Arriving by $slot · $tick';
  }
  if (lateNote.isEmpty) return core;
  return '$core. $lateNote';
}

/// Live countdown against the scheduled drop-off, e.g. "12 min left" / "8 min late".
String formatSlotCountdown(DateTime? slotStart, {DateTime? now}) {
  if (slotStart == null) return '';
  final current = now ?? DateTime.now();
  final diff = slotStart.difference(current);
  if (diff.inSeconds.abs() < 45) return 'Due now';
  if (diff.isNegative) return '${_humanDuration(diff.abs())} late';
  return '${_humanDuration(diff)} left';
}
