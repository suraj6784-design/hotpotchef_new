import 'package:shared_preferences/shared_preferences.dart';

const kCheckoutAddMembershipKey = 'checkout_add_membership';
const kFamilyMemberTitle = 'Family member';

double membershipOfferPrice(Map<String, dynamic>? offer) {
  if (offer == null) return 0;
  final flash = offer['flash_enabled'] == true;
  final offerPrice = _money(offer['offer_price_inr']);
  final listPrice = _money(offer['list_price_inr']);
  if (flash) return offerPrice > 0 ? offerPrice : listPrice;
  return listPrice > 0 ? listPrice : offerPrice;
}

String membershipMemberTitle(Map<String, dynamic>? offer) {
  final title = offer?['member_title']?.toString().trim();
  if (title != null && title.isNotEmpty) return title;
  return kFamilyMemberTitle;
}

bool dinerHasActiveMembership(Map<String, dynamic>? offer) {
  return offer?['active_member'] == true || offer?['reason']?.toString() == 'already_member';
}

/// Sell the plan only to diners who are not already in an active subscription period.
bool membershipOfferEligible(Map<String, dynamic>? offer) {
  if (offer == null) return false;
  if (dinerHasActiveMembership(offer)) return false;
  if (offer['eligible'] == false) return false;
  return (offer['plan_id']?.toString() ?? '').isNotEmpty;
}

Future<void> rememberAddMembershipAtCheckout() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kCheckoutAddMembershipKey, true);
}

Future<bool> consumeAddMembershipAtCheckout() async {
  final prefs = await SharedPreferences.getInstance();
  final add = prefs.getBool(kCheckoutAddMembershipKey) ?? false;
  if (add) await prefs.remove(kCheckoutAddMembershipKey);
  return add;
}

const kMembershipPlanMonths = [1, 3, 6, 9];

int membershipDaysLeft(DateTime? endsAt, {DateTime? now}) {
  if (endsAt == null) return 0;
  final start = now ?? DateTime.now();
  final seconds = endsAt.difference(start).inSeconds;
  if (seconds <= 0) return 0;
  return (seconds / 86400).ceil();
}

/// Plans are sold in 1, 3, 6 or 9 month blocks.
int membershipPlanMonthsFromDays(int? durationDays) {
  final days = durationDays ?? 90;
  final months = (days / 30).round().clamp(1, 9);
  return kMembershipPlanMonths.reduce(
    (best, option) => (months - option).abs() < (best - option).abs() ? option : best,
  );
}

int membershipDurationDaysForMonths(int months) {
  final plan = kMembershipPlanMonths.contains(months) ? months : 3;
  return plan * 30;
}

String membershipDaysLeftLabel({
  required DateTime? endsAt,
  int? durationDays,
  DateTime? now,
}) {
  final left = membershipDaysLeft(endsAt, now: now);
  final months = membershipPlanMonthsFromDays(durationDays);
  final plan = '$months month${months == 1 ? '' : 's'}';
  if (left <= 0) return '$plan plan ended';
  return 'Membership days left: $left · $plan plan';
}

String membershipPlanPeriodLabel(int? durationDays) {
  final months = membershipPlanMonthsFromDays(durationDays);
  return '$months month${months == 1 ? '' : 's'}';
}

/// GST at 18% included in the Family member price shown to diners.
double membershipGstIncluded(num amount) {
  final value = amount.toDouble();
  if (!value.isFinite || value <= 0) return 0;
  return ((value - (value / 1.18)) * 100).round() / 100;
}

String membershipGstLineLabel(num amount) {
  final gst = membershipGstIncluded(amount);
  if (gst <= 0) return 'GST included';
  return 'Includes GST ₹${gst.toStringAsFixed(0)} (18%)';
}

double _money(dynamic raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw?.toString() ?? '') ?? 0;
}
