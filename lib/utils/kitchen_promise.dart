const kDefaultPrepMinutes = 30;
const kDefaultTravelMinutes = 20;
const kLateOrderGraceMinutes = 15;
const kLateOrderCompensationCoins = 25;

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

String dinerLateOrderCopy(Map<String, dynamic> order, {DateTime? now}) {
  if (!orderQualifiesLateCompensation(order, now: now)) return '';
  final already = order['late_compensated_at'] != null ||
      (int.tryParse(order['late_compensation_coins']?.toString() ?? '') ?? 0) > 0;
  if (already) {
    return 'We missed the promise. $kLateOrderCompensationCoins HotPot Coins are on your wallet.';
  }
  return 'We missed the promise. $kLateOrderCompensationCoins HotPot Coins land when this order finishes.';
}
