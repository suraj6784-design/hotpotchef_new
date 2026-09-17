const kKitchenHourKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const kKitchenHourLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const kDefaultPrepMinutes = 30;
const kDefaultTravelMinutes = 20;
const kLateOrderGraceMinutes = 15;
const kLateOrderCompensationCoins = 25;

DateTime kitchenClockIst(DateTime? now) {
  final source = now ?? DateTime.now();
  return source.toUtc().add(const Duration(hours: 5, minutes: 30));
}

String kitchenHourKeyFor(DateTime ist) => kKitchenHourKeys[ist.weekday - 1];

int kitchenMinutesOfDay(DateTime ist) => ist.hour * 60 + ist.minute;

int? parseKitchenClockMinutes(String? raw) {
  final text = (raw ?? '').trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final hour = int.tryParse(match.group(1) ?? '') ?? -1;
  final minute = int.tryParse(match.group(2) ?? '') ?? -1;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

String formatKitchenClockMinutes(int minutes) {
  final clamped = minutes.clamp(0, 23 * 60 + 59);
  final hour = clamped ~/ 60;
  final minute = clamped % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String formatKitchenClockLabel(int minutes) {
  final hour = (minutes ~/ 60).clamp(0, 23);
  final minute = minutes % 60;
  final period = hour >= 12 ? 'PM' : 'AM';
  final twelve = hour % 12 == 0 ? 12 : hour % 12;
  return '$twelve:${minute.toString().padLeft(2, '0')} $period';
}

Map<String, dynamic> defaultKitchenWeeklyHours({int open = 11 * 60, int close = 22 * 60}) {
  return {
    for (final key in kKitchenHourKeys)
      key: {
        'closed': false,
        'open': formatKitchenClockMinutes(open),
        'close': formatKitchenClockMinutes(close),
      },
  };
}

Map<String, dynamic> parseKitchenWeeklyHours(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, dynamic>{};
  for (final key in kKitchenHourKeys) {
    final day = raw[key];
    if (day is Map) out[key] = Map<String, dynamic>.from(day);
  }
  return out;
}

bool kitchenHoursPosted(dynamic raw) => parseKitchenWeeklyHours(raw).isNotEmpty;

bool kitchenHoursAccepting(dynamic raw, {DateTime? now}) {
  final hours = parseKitchenWeeklyHours(raw);
  if (hours.isEmpty) return true;
  final ist = kitchenClockIst(now);
  final day = hours[kitchenHourKeyFor(ist)];
  if (day is! Map) return false;
  if (day['closed'] == true) return false;
  final open = parseKitchenClockMinutes(day['open']?.toString());
  final close = parseKitchenClockMinutes(day['close']?.toString());
  if (open == null || close == null || close <= open) return false;
  final current = kitchenMinutesOfDay(ist);
  return current >= open && current < close;
}

int kitchenPrepMinutes(Map<String, dynamic>? profile, [Map<String, dynamic>? meal]) {
  final mealPrep = int.tryParse(meal?['prep_minutes']?.toString() ?? '');
  if (mealPrep != null && mealPrep > 0) return mealPrep.clamp(5, 240);
  final kitchenPrep = int.tryParse(profile?['default_prep_minutes']?.toString() ?? '');
  if (kitchenPrep != null && kitchenPrep > 0) return kitchenPrep.clamp(5, 240);
  return kDefaultPrepMinutes;
}

int promisedEtaMinutes({
  required double distanceKm,
  int prepMinutes = kDefaultPrepMinutes,
}) {
  final travel = distanceKm <= 0
      ? kDefaultTravelMinutes
      : ((distanceKm / 20.0) * 60).round().clamp(8, 90);
  return prepMinutes.clamp(5, 240) + travel;
}

DateTime? orderPromisedAt(Map<String, dynamic> order, {DateTime? now}) {
  final stamped = DateTime.tryParse(order['promised_at']?.toString() ?? '');
  if (stamped != null) return stamped.toLocal();
  return null;
}

bool orderIsPastPromise(Map<String, dynamic> order, {DateTime? now, int graceMinutes = 0}) {
  final promised = orderPromisedAt(order, now: now);
  if (promised == null) return false;
  return promised
      .add(Duration(minutes: graceMinutes))
      .isBefore(now ?? DateTime.now());
}

bool orderQualifiesLateCompensation(Map<String, dynamic> order, {DateTime? now}) {
  return orderIsPastPromise(order, now: now, graceMinutes: kLateOrderGraceMinutes);
}

String kitchenWeeklyHoursLabel(dynamic raw) {
  final hours = parseKitchenWeeklyHours(raw);
  if (hours.isEmpty) return 'Hours not posted';
  String? shared;
  for (final key in kKitchenHourKeys) {
    final day = hours[key];
    if (day is! Map || day['closed'] == true) {
      shared = null;
      break;
    }
    final open = parseKitchenClockMinutes(day['open']?.toString());
    final close = parseKitchenClockMinutes(day['close']?.toString());
    if (open == null || close == null) {
      shared = null;
      break;
    }
    final label = '${formatKitchenClockLabel(open)}–${formatKitchenClockLabel(close)}';
    if (shared == null) {
      shared = label;
    } else if (shared != label) {
      shared = null;
      break;
    }
  }
  if (shared != null) return 'Daily $shared';
  final ist = kitchenClockIst(null);
  final today = hours[kitchenHourKeyFor(ist)];
  if (today is Map && today['closed'] != true) {
    final open = parseKitchenClockMinutes(today['open']?.toString());
    final close = parseKitchenClockMinutes(today['close']?.toString());
    if (open != null && close != null) {
      return 'Today ${formatKitchenClockLabel(open)}–${formatKitchenClockLabel(close)}';
    }
  }
  return 'See weekly hours';
}

String dinerLateOrderCopy(Map<String, dynamic> order, {DateTime? now}) {
  if (!orderQualifiesLateCompensation(order, now: now)) return '';
  final already = order['late_compensated_at'] != null ||
      (int.tryParse(order['late_compensation_coins']?.toString() ?? '') ?? 0) > 0;
  if (already) {
    return 'We missed the promise. $kLateOrderCompensationCoins HotPot Coins are on your wallet.';
  }
  return 'We missed the promise. $kLateOrderCompensationCoins HotPot Coins land when this order finishes.';
}
