// lib/utils/helpers.dart

import 'dart:convert';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'delivery_fee.dart';
import 'kitchen_promise.dart';
import 'fssai_certificate_scan.dart';
import 'network.dart';
import 'notification_copy.dart';
import 'membership.dart';
import 'pricing_calculator.dart';
import 'meal_nutrition.dart';
import 'service_area.dart';
import '../models/app_role.dart';
import '../models/order_status.dart';
import '../models/cart_enums.dart';
import '../models/pricing_models.dart';

// Export the theme so all screens automatically inherit it
export 'app_theme.dart';
export 'kitchen_promise.dart'; 
part 'helpers_feed.dart';
part 'helpers_slots.dart';
part 'helpers_offers.dart';
part 'helpers_address.dart';


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

  static String shortDateTime(DateTime dt) => formatAppDateTime(dt);
}

/// One display pattern for every diner/chef/driver-facing order timestamp
/// (placed, delivery slot, delivered, cancelled).
const String kAppDatePattern = 'dd MMM yyyy';
const String kAppTimePattern = 'hh:mm a';
const String kAppDateTimePattern = 'dd MMM yyyy, hh:mm a';

/// Stored calendar day. UI always goes through [formatAppDate] / [formatAppDateTime].
const String kAppDateKeyPattern = 'yyyy-MM-dd';

String formatAppDate(DateTime date) => DateFormat(kAppDatePattern).format(date.toLocal());

String formatAppTime(DateTime date) => DateFormat(kAppTimePattern).format(date.toLocal());

String formatAppDateTime(DateTime date) => DateFormat(kAppDateTimePattern).format(date.toLocal());

String formatAppDateKey(DateTime date) => DateFormat(kAppDateKeyPattern).format(date.toLocal());

bool isSameAppCalendarDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// Same calendar day → `hh:mm a`; otherwise `dd MMM yyyy, hh:mm a`.
String formatAppWhen(DateTime date, {DateTime? now}) {
  final local = date.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  if (isSameAppCalendarDay(local, current)) return formatAppTime(local);
  return formatAppDateTime(local);
}

String formatAppTimeOfDay(TimeOfDay time) {
  return formatAppTime(DateTime(2026, 1, 1, time.hour, time.minute));
}

String normalizeAccountStatus(String? status) {
  final value = (status ?? 'active').trim().toLowerCase();
  if (value.isEmpty) return 'active';
  return value;
}

bool accountIsDeactivated(String? status) => normalizeAccountStatus(status) == 'deactivated';

String accountActivationTileTitle(String? status) {
  return accountIsDeactivated(status) ? 'Activate account' : 'Deactivate account';
}

String accountActivationTileSubtitle(String? status) {
  return accountIsDeactivated(status)
      ? 'Turn your diner account back on to place orders'
      : 'Pause ordering until you activate again';
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

String mealShareUri(String? mealId) {
  final id = mealId?.trim() ?? '';
  if (id.isEmpty) return '';
  // HTTPS so WhatsApp / Instagram / Messages auto-link and open the app (or site).
  return '$kMealShareWebBase/meal/$id';
}

/// In-app custom scheme (Android/iOS URL type). Prefer [mealShareUri] for shared cards.
String mealShareAppUri(String? mealId) {
  final id = mealId?.trim() ?? '';
  if (id.isEmpty) return '';
  return 'hotpotchef://app/meal/$id';
}

String chefShareUri(String? chefId) {
  final id = chefId?.trim() ?? '';
  if (id.isEmpty) return '';
  return '$kMealShareWebBase/chef/$id';
}

String chefShareAppUri(String? chefId) {
  final id = chefId?.trim() ?? '';
  if (id.isEmpty) return '';
  return 'hotpotchef://app/chef/$id';
}

/// Public web host used in share cards (must match Play / site deep-link setup).
const kMealShareWebBase = 'https://hotpotchef.com';

/// Must also be allow-listed in the Supabase Auth redirect URLs.
const passwordResetRedirectUri = 'hotpotchef://app/reset-password';

bool isPasswordRecoveryPath(String path) {
  return path == '/reset-password' || path == '/reset-callback';
}

String? resetPasswordValidationError({
  required String password,
  required String confirm,
}) {
  if (password.trim().length < 8) {
    return 'Password must be at least 8 characters long.';
  }
  if (password.trim() != confirm.trim()) {
    return 'Passwords do not match.';
  }
  return null;
}

const double kReferralBonusCoins = 50;

String? normalizeReferralCode(String? raw) {
  final code = (raw ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  return code.isEmpty ? null : code;
}

bool isPlausibleReferralCode(String code) {
  return RegExp(r'^[A-Z0-9]{6,16}$').hasMatch(code);
}

String generateReferralCode([Random? random]) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final rnd = random ?? Random();
  return 'CHEF${List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join()}';
}

String? sanitizeReferredBy({String? referredBy, String? ownCode}) {
  final code = normalizeReferralCode(referredBy);
  final own = normalizeReferralCode(ownCode);
  if (code == null) return null;
  if (own != null && code == own) return null;
  return code;
}

String referralInviteAppUri(String code) {
  final normalized = normalizeReferralCode(code) ?? code;
  return 'hotpotchef://app/auth?ref=$normalized';
}

/// HTTPS so WhatsApp / Instagram / Messages auto-link the invite.
String referralInviteUri(String code) {
  final normalized = Uri.encodeQueryComponent(normalizeReferralCode(code) ?? code);
  return '$kMealShareWebBase/auth?ref=$normalized';
}

String referralInviteText(String code) {
  final display = normalizeReferralCode(code) ?? code.trim().toUpperCase();
  return 'Craving authentic home-cooked food? Join HotPotChef with my code $display. '
      'We both get ${kReferralBonusCoins.toInt()} HotPot Coins when you place your first order.\n'
      '${referralInviteUri(display)}';
}

double referralCoinsFromRewardedFriends(int rewardedFriends, [double bonus = kReferralBonusCoins]) {
  if (rewardedFriends <= 0) return 0;
  return rewardedFriends * bonus;
}

String referralCardStatsLabel({required int sharedCount, required double coinsCredited}) {
  final shared = sharedCount < 0 ? 0 : sharedCount;
  final coins = coinsCredited < 0 ? 0 : coinsCredited.toInt();
  return '$shared shared · $coins coins';
}

bool referralOrderCountsTowardBonus(String? status) {
  final s = (status ?? '').toLowerCase();
  if (s.contains('cancel') || s.contains('reject')) return false;
  return true;
}

int referralLiveOrderCount(Iterable<dynamic> orders) {
  var count = 0;
  for (final row in orders) {
    if (row is! Map) continue;
    if (referralOrderCountsTowardBonus(row['status']?.toString())) count++;
  }
  return count;
}

bool canGrantFirstOrderReferralBonus({
  required String? referredBy,
  DateTime? referralRewardedAt,
  required int liveOrderCount,
  required bool referrerFound,
}) {
  if (referralRewardedAt != null) return false;
  final code = normalizeReferralCode(referredBy);
  if (code == null) return false;
  if (!referrerFound) return false;
  return liveOrderCount == 1;
}

bool roleUsesReferral(String? role) {
  switch (role?.trim().toLowerCase()) {
    case 'chef':
    case 'cook':
    case 'driver':
    case 'delivery partner':
    case 'delivery_partner':
      return false;
    default:
      return true;
  }
}

/// Current in-app Terms / Privacy consent copy version.
const kLegalConsentVersion = '2026-09-07';

Map<String, dynamic> legalConsentFields({DateTime? at}) {
  final stamp = (at ?? DateTime.now()).toUtc().toIso8601String();
  return {
    'terms_accepted_at': stamp,
    'privacy_accepted_at': stamp,
    'legal_consent_version': kLegalConsentVersion,
  };
}

Map<String, dynamic> signupUserPayload({
  required String id,
  required String email,
  required String name,
  required String phone,
  required String role,
  String? referredBy,
  String? referralCode,
  String? createdAt,
  bool recordLegalConsent = false,
}) {
  final customer = roleUsesReferral(role);
  return {
    'id': id,
    'email': email,
    'name': name,
    'full_name': name,
    'phone': phone,
    'role': role,
    if (createdAt != null) 'created_at': createdAt,
    if (customer && referredBy != null) 'referred_by': referredBy,
    if (customer && referralCode != null) 'referral_code': referralCode,
    if (recordLegalConsent) ...legalConsentFields(),
  };
}

String mealShareSlotLine(Map<String, dynamic> meal) {
  final slot = formatDeliverySlotLabel(meal);
  return slot.trim().isEmpty ? 'ASAP' : slot.trim();
}

String? mealSharePromoCode(Map<String, dynamic> meal) {
  return PricingCalculator.mealPromoCode(meal);
}

/// WhatsApp-ready card: dish, kitchen, price, slot, promo, 2-tap link.
String mealShareText(Map<String, dynamic> meal) {
  final title = mealDisplayTitle(meal);
  final chef = chefDisplayName(meal);
  final price = PricingCalculator.effectiveUnitPrice(meal, 1);
  final slot = mealShareSlotLine(meal);
  final code = mealSharePromoCode(meal);
  final link = mealShareUri(meal['id']?.toString() ?? mealIdFromOrderItem(meal));
  final priceSlot = price > 0 ? '₹${price.toStringAsFixed(0)} · $slot' : slot;
  final nutrition = mealNutritionFacts(meal).compactLine;
  final lines = <String>[
    isFestivalHamper(meal)
        ? 'Festival hamper: $title from $chef'
        : (isSocietyNight(meal)
            ? 'Society night at ${societyNightLabel(meal)}: $title from $chef'
            : (isShelfItem(meal)
                ? 'Shelf from home (${shelfItemKind(meal)}): $title from $chef'
                : '$title from $chef')),
    priceSlot,
    if (nutrition.isNotEmpty) nutrition,
    if (code != null) 'Use code $code at checkout',
    isFestivalHamper(meal)
        ? 'Gift a home kitchen box — order in 2 taps on HotPotChef'
        : (isSocietyNight(meal)
            ? 'One building, one kitchen drop — order in 2 taps on HotPotChef'
            : (isShelfItem(meal)
                ? 'Pickle, masala & pantry from home kitchens — order in 2 taps on HotPotChef'
                : 'Order in 2 taps on HotPotChef')),
    if (link.isNotEmpty) link,
  ];
  return lines.join('\n');
}

Uri mealWhatsAppShareUri(String text) {
  return Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
}

String? normalizeFssaiNumber(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length != 14) return null;
  if (digits[0] != '1' && digits[0] != '2') return null;
  return digits;
}

String normalizeFssaiVerificationStatus(String? raw) {
  final status = (raw ?? '').trim().toLowerCase();
  if (status == 'pending' || status == 'verified' || status == 'rejected' || status == 'unsubmitted') {
    return status;
  }
  return 'unsubmitted';
}

String fssaiVerificationLabel(String? status) {
  switch (normalizeFssaiVerificationStatus(status)) {
    case 'verified':
      return 'FSSAI verified';
    case 'pending':
      return 'FSSAI proof under review';
    case 'rejected':
      return 'FSSAI rejected — re-upload proof';
    default:
      return 'Upload FSSAI proof to publish';
  }
}

/// Publish requires a valid number, uploaded proof, and ops-verified status.
bool chefCanPublishWithFssai({
  String? fssaiNumber,
  String? proofUrl,
  String? verificationStatus,
  DateTime? validUntil,
  DateTime? now,
}) {
  return chefFssaiPublishBlockReason(
        fssaiNumber: fssaiNumber,
        proofUrl: proofUrl,
        verificationStatus: verificationStatus,
        validUntil: validUntil,
        now: now,
      ) ==
      null;
}

/// Null when the chef may publish. Otherwise a chef-facing reason.
String? chefFssaiPublishBlockReason({
  String? fssaiNumber,
  String? proofUrl,
  String? verificationStatus,
  DateTime? validUntil,
  DateTime? now,
}) {
  if (normalizeFssaiNumber(fssaiNumber) == null) {
    return 'Add a valid 14-digit FSSAI licence number in Chef Profile, then try again.';
  }
  if ((proofUrl ?? '').trim().isEmpty) {
    return 'Upload your FSSAI licence proof in Chef Profile. Publishing requires ops verification.';
  }
  if (fssaiLicenceIsExpired(validUntil, now: now)) {
    return 'Your FSSAI licence has expired. Upload a current certificate in Chef Profile.';
  }
  switch (normalizeFssaiVerificationStatus(verificationStatus)) {
    case 'verified':
      return null;
    case 'pending':
      return 'FSSAI proof is under review (typically 1 business day). Publishing unlocks after HotPotChef verifies.';
    case 'rejected':
      return 'Your FSSAI proof was rejected. Upload a clear licence photo in Chef Profile.';
    default:
      return 'HotPotChef still needs to verify your FSSAI proof in Chef Profile before you can publish.';
  }
}

/// Honest diner-facing FSSAI line (never imply verified without ops status).
String dinerFssaiTrustLabel({
  String? fssaiNumber,
  String? verificationStatus,
  DateTime? validUntil,
  DateTime? now,
}) {
  final number = (fssaiNumber ?? '').trim();
  final status = normalizeFssaiVerificationStatus(verificationStatus);
  if (number.isEmpty) return 'FSSAI not listed';
  if (fssaiLicenceIsExpired(validUntil, now: now)) {
    return 'FSSAI licence expired · $number';
  }
  final until = dinerFssaiValidUntilCaption(validUntil);
  switch (status) {
    case 'verified':
      return until == null ? 'FSSAI verified · $number' : 'FSSAI verified · $number · $until';
    case 'pending':
      return 'FSSAI proof under review · $number';
    case 'rejected':
      return 'FSSAI not verified · $number';
    default:
      return until == null ? 'FSSAI listed · $number' : 'FSSAI listed · $number · $until';
  }
}

String? dinerFssaiValidUntilCaption(DateTime? validUntil) {
  if (validUntil == null) return null;
  return 'valid until ${formatAppDate(validUntil)}';
}

bool dinerFssaiIsVerified(
  String? verificationStatus, {
  DateTime? validUntil,
  DateTime? now,
}) {
  if (normalizeFssaiVerificationStatus(verificationStatus) != 'verified') return false;
  return !fssaiLicenceIsExpired(validUntil, now: now);
}

/// Short feed-card mark. Empty when the kitchen is not ops-verified.
String dinerFssaiCardChip({
  String? verificationStatus,
  DateTime? validUntil,
  DateTime? now,
}) {
  return dinerFssaiIsVerified(verificationStatus, validUntil: validUntil, now: now) ? 'Verified' : '';
}

/// 0–100 kitchen trust from FSSAI + review velocity. Not a hygiene lab score.
int kitchenTrustScore({
  String? verificationStatus,
  DateTime? validUntil,
  ChefRatingSummary ratings = const ChefRatingSummary(),
  DateTime? now,
}) {
  var score = 0;
  final verified = dinerFssaiIsVerified(verificationStatus, validUntil: validUntil, now: now);
  if (verified) {
    final until = validUntil;
    if (until == null) {
      score += 45;
    } else {
      final n = (now ?? DateTime.now()).toLocal();
      final days = until.difference(DateTime(n.year, n.month, n.day)).inDays;
      if (days < 0) {
        score += 10;
      } else if (days <= 30) {
        score += 40;
      } else {
        score += 50;
      }
    }
  } else if (normalizeFssaiVerificationStatus(verificationStatus) == 'pending') {
    score += 20;
  }
  if (ratings.hasReviews) {
    score += ((ratings.average / 5) * 35).round().clamp(0, 35);
    score += ((ratings.count.clamp(0, 20) / 20) * 15).round();
  }
  return score.clamp(0, 100);
}

String kitchenTrustLabel(int score) => 'Kitchen trust $score/100';

final _panNumberRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');

bool isValidPan(String? raw) {
  final cleaned = (raw ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  return _panNumberRegex.hasMatch(cleaned);
}

String maskPan(String? raw) {
  final cleaned = (raw ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  if (cleaned.length < 4) return cleaned.isEmpty ? '' : '****';
  return '******${cleaned.substring(cleaned.length - 4)}';
}

String maskBankAccount(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return digits.isEmpty ? '' : '****';
  return 'XXXXXX${digits.substring(digits.length - 4)}';
}

bool deliveryOtpMatches(String? expected, String? entered) {
  final a = (expected ?? '').replaceAll(RegExp(r'\D'), '');
  final b = (entered ?? '').replaceAll(RegExp(r'\D'), '');
  if (a.length < 4 || b.length < 4) return false;
  return a == b;
}

final _deliveryPinLine = RegExp(
  r'^(?:delivery\s*pin|otp)\s*:\s*\d{4}\b',
  caseSensitive: false,
);

bool isDeliveryPinInstructionLine(String line) {
  return _deliveryPinLine.hasMatch(line.trim());
}

/// Kitchen and driver notes must not include the diner dropoff PIN.
String kitchenFacingOrderNotes(String? raw) {
  return _notesWithoutDeliveryPin(raw);
}

String driverFacingOrderNotes(String? raw) {
  return _notesWithoutDeliveryPin(raw);
}

/// Realtime `orders` rows include `delivery_otp`; kitchens must not see the PIN.
Map<String, dynamic> chefFacingOrderRow(Map<String, dynamic> order) {
  final copy = Map<String, dynamic>.from(order);
  copy.remove('delivery_otp');
  final notes = copy['special_instructions']?.toString();
  if (notes != null && notes.isNotEmpty) {
    copy['special_instructions'] = kitchenFacingOrderNotes(notes);
  }
  return copy;
}

String _notesWithoutDeliveryPin(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return '';
  final kept = text
      .split(RegExp(r'\n| · '))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !isDeliveryPinInstructionLine(line))
      .toList();
  return kept.join('\n').trim();
}

const kPackagingOpsStatuses = <String>[
  'Open',
  'Confirmed',
  'Packed',
  'Out for Delivery',
  'Fulfilled',
  'Rejected',
  'Cancelled',
];

String packagingRequestStatusLabel(String? status) {
  final raw = (status ?? 'Open').trim();
  if (raw.isEmpty) return 'Open';
  return raw;
}

String plateShareDishLabel(Iterable<dynamic> items) {
  final titles = <String>[];
  for (final raw in items) {
    if (raw is! Map) continue;
    final title = mealDisplayTitle(Map<String, dynamic>.from(raw), fallback: '');
    if (title.isEmpty) continue;
    if (!titles.contains(title)) titles.add(title);
  }
  if (titles.isEmpty) return 'home-cooked food';
  if (titles.length == 1) return titles.first;
  if (titles.length == 2) return '${titles[0]} & ${titles[1]}';
  return '${titles.first} + ${titles.length - 1} more';
}

String? plateShareMealId(Iterable<dynamic> items) {
  for (final raw in items) {
    if (raw is! Map) continue;
    final id = mealIdFromOrderItem(Map<String, dynamic>.from(raw));
    if (id != null && id.isNotEmpty) return id;
  }
  return null;
}

String? plateShareFssaiFromItems(Iterable<dynamic> items) {
  for (final raw in items) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    for (final key in const ['fssai_number', 'fssai', 'chef_fssai']) {
      final normalized = normalizeFssaiNumber(item[key]?.toString());
      if (normalized != null) return normalized;
    }
    for (final nestedKey in const ['rawMealDetails', 'mealDetails', 'meal_details']) {
      final nested = item[nestedKey];
      if (nested is! Map) continue;
      final normalized = normalizeFssaiNumber(nested['fssai_number']?.toString());
      if (normalized != null) return normalized;
    }
  }
  return null;
}

/// After-delivery card: dish, chef, FSSAI, deep link — for WhatsApp / Instagram.
String plateShareText({
  required String chefName,
  required Iterable<dynamic> items,
  String? fssai,
}) {
  final chef = chefName.trim().isEmpty ? 'a home kitchen' : chefName.trim();
  final dish = plateShareDishLabel(items);
  final licence = normalizeFssaiNumber(fssai) ?? plateShareFssaiFromItems(items);
  final link = mealShareUri(plateShareMealId(items));
  final lines = <String>[
    'Just finished $dish from $chef on HotPotChef',
    if (licence != null) 'FSSAI $licence',
    'Home kitchen food — not restaurant haste.',
    'Order in 2 taps:',
    if (link.isNotEmpty) link,
  ];
  return lines.join('\n');
}

/// Society / office / friends group-cart place kinds.
const kGroupPlaceKinds = ['society', 'office', 'friends'];

String normalizeGroupPlaceKind(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (kGroupPlaceKinds.contains(value)) return value;
  return 'friends';
}

String groupPlaceKindLabel(String? kind) {
  switch (normalizeGroupPlaceKind(kind)) {
    case 'society':
      return 'Society lunch';
    case 'office':
      return 'Office lunch';
    default:
      return 'Group order';
  }
}

String groupPlaceKindHint(String? kind) {
  switch (normalizeGroupPlaceKind(kind)) {
    case 'society':
      return 'Building / wing / flat';
    case 'office':
      return 'Floor / desk bay / meeting room';
    default:
      return 'Where should we drop?';
  }
}

final _groupRoomCodePattern = RegExp(r'GRP-[A-Z0-9]{6}\b', caseSensitive: false);

/// Pulls `GRP-XXXXXX` out of a typed code, a pasted invite, or a group link.
String? parseGroupRoomCode(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri != null && uri.pathSegments.length > 1) {
    final segments = uri.pathSegments;
    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i].toLowerCase() != 'group') continue;
      final fromPath = _groupRoomCodePattern.firstMatch(segments[i + 1].toUpperCase());
      if (fromPath != null) return fromPath.group(0)!.toUpperCase();
    }
  }
  final match = _groupRoomCodePattern.firstMatch(text.toUpperCase());
  return match?.group(0)?.toUpperCase();
}

/// HTTPS link teammates tap to land in this group cart.
String groupCartShareUri(String? roomCode) {
  final code = parseGroupRoomCode(roomCode);
  if (code == null || code == 'GRP-XXXXXX') return '';
  return '$kMealShareWebBase/group/$code';
}

/// Only a diner group-join path may be used as a post-sign-in return.
String? dinerGroupReturnPath(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.hasScheme || uri.host.isNotEmpty) return null;
  if (uri.pathSegments.length != 2 || uri.pathSegments.first != 'group') return null;
  final code = parseGroupRoomCode(uri.pathSegments[1]);
  if (code == null) return null;
  return '/group/$code';
}

/// WhatsApp invite for one-host society/office carts.
String societyGroupInviteText({
  required String roomCode,
  String? placeKind,
  String? placeLabel,
  String? dropoffNote,
  String? timeSlot,
}) {
  final code = roomCode.trim().toUpperCase();
  final kind = normalizeGroupPlaceKind(placeKind);
  final title = groupPlaceKindLabel(kind);
  final place = (placeLabel ?? '').trim();
  final drop = (dropoffNote ?? '').trim();
  final slot = (timeSlot ?? '').trim();
  final headline = place.isEmpty ? title : '$title at $place';
  final link = groupCartShareUri(code);
  return [
    headline,
    'Join my HotPotChef group cart: $code',
    if (link.isNotEmpty) link,
    if (slot.isNotEmpty) 'Slot: $slot',
    if (drop.isNotEmpty) 'Drop: $drop',
    'Add your plates — I pay once at checkout.',
  ].join('\n');
}

String formatOrderId(String? rawOrderId, String fallbackId) {
  if (rawOrderId != null && rawOrderId.isNotEmpty) {
    return rawOrderId.length > 8 ? rawOrderId.substring(0, 8).toUpperCase() : rawOrderId.toUpperCase();
  }
  return fallbackId.length > 8 ? fallbackId.substring(0, 8).toUpperCase() : fallbackId.toUpperCase();
}

/// Order-group chat (chef / diner / driver) closes after delivery or cancel.
bool orderAllowsPartyChat(String? status) {
  final s = (status ?? '').toLowerCase().trim();
  if (s.isEmpty) return true;
  // Avoid matching "Out for Delivery" via the "deliver" substring.
  if (s == 'delivered' || s.contains('delivered') || s.contains('complet')) return false;
  if (s.contains('cancel') || s.contains('refund') || s.contains('reject')) return false;
  return true;
}

/// Phone dial is only for active fulfilment — not for fishing contacts pre-prep or post-delivery.
bool orderAllowsPhoneCall(String? status) {
  if (!orderAllowsPartyChat(status)) return false;
  final s = (status ?? '').toLowerCase().trim();
  if (s.isEmpty) return false;
  return s.contains('confirm') ||
      s.contains('prepar') ||
      s.contains('cook') ||
      s.contains('ready') ||
      s.contains('assign') ||
      s.contains('accept') ||
      s.contains('heading') ||
      s.contains('pickup') ||
      s.contains('picked') ||
      s.contains('out for') ||
      s == 'out' ||
      (s.contains('out') && s.contains('deliver'));
}

final _offAppPayPattern = RegExp(
  r'(?:\bupi\b|\bpaytm\b|\bgpay\b|\bgoogle\s*pay\b|\bphonepe\b|\bphone\s*pe\b|'
  r'@oksbi|@okicici|@okhdfc|@paytm|'
  r'wa\.me|whatsapp\.me|whats\s*app\s*me|message\s+me\s+on\s+wa|'
  r'pay\s+(?:me\s+)?(?:outside|offline|directly|on\s+whatsapp|via\s+upi)|'
  r'(?:next\s+time|from\s+now).{0,40}(?:whatsapp|upi|cash)|'
  r'(?:send|pay).{0,20}(?:to\s+my\s+number|qr)|'
  r'\b\d{10}\b.{0,20}(?:upi|pay|gpay|phonepe))',
  caseSensitive: false,
);

bool messageSolicitsOffAppPayment(String? text) {
  final raw = (text ?? '').trim();
  if (raw.length < 4) return false;
  return _offAppPayPattern.hasMatch(raw);
}

const kPayInAppChatNotice =
    'Pay only in the HotPotChef app. In-app checkout keeps refunds, HotPot Coins, delivery tracking, and Support. Do not take this order off the app.';

String offAppPaymentNudgeCopy() =>
    'This looks like an off-app payment request. HotPotChef may suspend accounts that move paid customers off the platform. Send anyway only if you are discussing something else.';

/// Stored `users.role` values for kitchens. Avoid lowercase `chef` in PostgREST
/// filters — invalid enum values can fail the whole query.
const kStoredChefRoles = ['Chef', 'Cook'];

/// True when a chef/kitchen label matches a diner search string.
bool chefNameMatchesQuery(String? query, Map<String, dynamic>? chefOrMeal) {
  final q = (query ?? '').trim().toLowerCase();
  if (q.isEmpty || chefOrMeal == null) return false;
  final compactQ = q.replaceAll(RegExp(r'\s+'), '');
  for (final key in const [
    'chef_name',
    'kitchen_name',
    'local_kitchen_name',
    'name',
    'full_name',
    'display_name',
  ]) {
    final value = chefOrMeal[key]?.toString().trim().toLowerCase() ?? '';
    if (value.isEmpty) continue;
    if (value.contains(q) || value.replaceAll(RegExp(r'\s+'), '').contains(compactQ)) {
      return true;
    }
  }
  return false;
}

/// Meal rows: only kitchen labels, not a diner `name` copied onto the meal.
bool mealChefLabelMatchesQuery(String? query, Map<String, dynamic>? meal) {
  final q = (query ?? '').trim().toLowerCase();
  if (q.isEmpty || meal == null) return false;
  final compactQ = q.replaceAll(RegExp(r'\s+'), '');
  for (final key in const ['chef_name', 'kitchen_name', 'local_kitchen_name']) {
    final value = meal[key]?.toString().trim().toLowerCase() ?? '';
    if (value.isEmpty) continue;
    if (value.contains(q) || value.replaceAll(RegExp(r'\s+'), '').contains(compactQ)) {
      return true;
    }
  }
  return false;
}

/// Home / bulk kitchen search: diners and drivers must not appear as chefs.
bool isChefAccount(Map<String, dynamic>? data) {
  if (data == null) return false;
  return AppRole.parse(data['role']?.toString()) == AppRole.chef;
}


Future<void> copyOrderNumber(BuildContext context, String orderNumber) async {
  final text = orderNumber.trim();
  if (text.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Copied $text')),
  );
}

Widget orderIdCopyRow(BuildContext context, String orderNumber) {
  return InkWell(
    onTap: () => copyOrderNumber(context, orderNumber),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Order ID: $orderNumber',
          style: TextStyle(color: AppTheme.onSurfaceOf(context).withValues(alpha: 0.65), fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Icon(Icons.copy, size: 14, color: AppTheme.onSurfaceOf(context).withValues(alpha: 0.65)),
      ],
    ),
  );
}

/// Orders store the UUID in `id`. Enriched line items copy it to `order_id`.
String? resolvedOrderId(Map<String, dynamic>? data) {
  if (data == null) return null;
  final orderId = data['order_id']?.toString().trim() ?? '';
  if (orderId.isNotEmpty) return orderId;
  final id = data['id']?.toString().trim() ?? '';
  return id.isEmpty ? null : id;
}

String? mealIdFromOrderItem(Map<String, dynamic>? item) {
  if (item == null) return null;
  for (final key in const ['source_meal_id', 'meal_id', 'mealId', 'id']) {
    final value = item[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return null;
}

String? otherChatParticipantId(Iterable<Map<String, dynamic>> messages, String? myId) {
  for (final message in messages) {
    final id = message['sender_id']?.toString() ?? '';
    if (id.isNotEmpty && id != myId) return id;
  }
  return null;
}

/// Prefer the user we opened chat with so Call works before anyone has typed.
String? resolveChatCallTarget({
  String? knownOtherUserId,
  required Iterable<Map<String, dynamic>> messages,
  String? myId,
}) {
  final known = knownOtherUserId?.trim() ?? '';
  if (known.isNotEmpty && known != myId) return known;
  return otherChatParticipantId(messages, myId);
}

String chatPath(
  String roomId, {
  String roomName = 'Chat',
  String? otherUserId,
  Iterable<String>? memberIds,
  bool isGroup = false,
}) {
  final members = (memberIds ?? const <String>[])
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  return Uri(
    path: '/chat/$roomId',
    queryParameters: {
      'roomName': roomName,
      if (otherUserId != null && otherUserId.trim().isNotEmpty) 'otherUserId': otherUserId.trim(),
      if (members.isNotEmpty) 'memberIds': members.join(','),
      if (isGroup || members.length > 1) 'group': '1',
    },
  ).toString();
}

int customerHubTabIndex(String? tab) {
  switch (tab?.trim().toLowerCase()) {
    case 'cart':
      return 1;
    case 'orders':
      return 2;
    case 'account':
    case 'profile':
      return 3;
    case 'alerts':
    case 'notifications':
      return 4;
    default:
      return 0;
  }
}

int chefHubTabIndex(String? tab) {
  switch (tab?.trim().toLowerCase()) {
    case 'orders':
      return 1;
    case 'profile':
    case 'account':
      return 2;
    case 'alerts':
    case 'notifications':
      return 3;
    case 'menu':
      return 4;
    case 'dispatch':
      return 5;
    case 'history':
      return 6;
    case 'leads':
      return 7;
    case 'supplies':
      return 8;
    default:
      return 0;
  }
}

bool isPastOrderStatus(String? status) {
  final current = (status ?? '').trim().toLowerCase();
  if (current.contains('out for delivery') || current.contains('out_for_delivery')) {
    return false;
  }
  return current.contains('delivered') ||
      current.contains('complet') ||
      current.contains('cancel') ||
      current.contains('reject') ||
      current.contains('refund');
}

/// Flatten `user_notifications.data` so [alertOpenPath] can open the matching hub.
Map<String, String?> alertDataFromNotificationRow(Map<String, dynamic> row) {
  final data = <String, String?>{
    'kind': row['kind']?.toString(),
    'type': row['kind']?.toString(),
  };
  for (final key in const [
    'order_id',
    'meal_id',
    'request_id',
    'lead_id',
    'chef_id',
    'kitchen_id',
    'status',
    'role',
  ]) {
    final value = row[key];
    if (value == null || value is Map || value is List) continue;
    data[key] = value.toString();
  }
  final extra = row['data'];
  if (extra is Map) {
    extra.forEach((key, value) {
      if (value == null || value is Map || value is List) return;
      data[key.toString()] = value.toString();
    });
  }
  return data;
}

/// Chat pushes open the Order# room. Order and lead pushes land on the matching hub tab.
String? alertOpenPath(Map<String, String?> data, {String? role}) {
  final mealId = (data['meal_id'] ?? '').trim();
  if (mealId.isNotEmpty) {
    return chatPath(
      mealId,
      roomName: orderGroupAlertTitle(mealId),
      isGroup: true,
    );
  }

  final requestId = (data['request_id'] ?? data['lead_id'] ?? '').trim();
  final parsedRole = (role ?? '').trim().toLowerCase();
  if (requestId.isNotEmpty) {
    return parsedRole == 'chef' ? '/chef-hub?tab=leads' : '/customer-hub?tab=orders';
  }

  final kitchenId = (data['chef_id'] ?? data['kitchen_id'] ?? '').trim();
  if (kitchenId.isNotEmpty && (data['order_id'] ?? '').trim().isEmpty) {
    return '/customer-hub';
  }

  final kind = (data['kind'] ?? data['type'] ?? '').trim().toLowerCase();
  if (kind == 'kyc_pending' || kind == 'kyc') {
    final fromPayload = (data['role'] ?? '').trim().toLowerCase();
    if (parsedRole.contains('driver') ||
        parsedRole.contains('delivery') ||
        fromPayload.contains('driver')) {
      return '/driver-profile';
    }
    return '/chef-profile';
  }

  final orderId = (data['order_id'] ?? '').trim();
  if (orderId.isEmpty) return null;
  final past = isPastOrderStatus(data['status']);
  if (parsedRole == 'chef' || parsedRole.contains('cook')) {
    return past ? '/chef-hub?tab=history' : '/chef-hub?tab=orders';
  }
  if (parsedRole.contains('driver') || parsedRole.contains('delivery')) return '/driver-hub';
  if (!past && isLiveTrackingStatus(data['status'])) {
    return '/tracking?orderId=$orderId';
  }
  return past ? '/order-history' : '/customer-hub?tab=orders';
}

bool isLiveTrackingStatus(String? status) {
  switch (OrderStatus.canonical(status)) {
    case OrderStatus.readyForPickup:
    case OrderStatus.driverAssigned:
    case OrderStatus.headingToKitchen:
    case OrderStatus.outForDelivery:
      return true;
    default:
      return false;
  }
}


bool _haystackHasAny(String haystack, Iterable<String> needles) {
  for (final needle in needles) {
    if (needle.isEmpty) continue;
    if (haystack.contains(needle)) return true;
  }
  return false;
}

bool isStackAlertPath(String path) {
  final route = Uri.tryParse(path)?.path ?? path;
  return route.startsWith('/chat/') ||
      route.startsWith('/meal/') ||
      route.startsWith('/chef/') ||
      route.startsWith('/group/') ||
      route == '/chef-profile' ||
      route == '/driver-profile' ||
      route == '/cart' ||
      route.startsWith('/cart?');
}

class ChatInboxItem {
  const ChatInboxItem({
    required this.roomId,
    required this.title,
    required this.preview,
    required this.memberIds,
    this.otherUserId,
    this.lastAt,
    this.lastSenderId,
    this.isGroup = true,
  });

  final String roomId;
  final String title;
  final String preview;
  final List<String> memberIds;
  final String? otherUserId;
  final DateTime? lastAt;
  final String? lastSenderId;
  final bool isGroup;
}

List<String> cateringRequestChatMemberIds(
  Map<String, dynamic> request, {
  Iterable<String> quotingChefIds = const [],
}) {
  final members = <String>{
    if ((request['customer_id']?.toString() ?? '').isNotEmpty) request['customer_id'].toString(),
    if ((request['accepted_chef_id']?.toString() ?? '').isNotEmpty) request['accepted_chef_id'].toString(),
    for (final id in quotingChefIds)
      if (id.trim().isNotEmpty) id.trim(),
  };
  return members.toList();
}

bool orderChatIsActive(Map<String, dynamic> order) {
  final s = (order['status']?.toString() ?? '').trim().toLowerCase();
  if (s.isEmpty) return true;
  if (s.contains('cancel') || s.contains('reject') || s.contains('refund')) return false;
  if (s.contains('out for delivery') || s.contains('out_for_delivery')) return true;
  if (s.contains('delivered') || s.contains('completed')) return false;
  return true;
}

bool cateringChatIsActive(Map<String, dynamic> request) {
  final s = (request['status']?.toString() ?? '').trim().toLowerCase();
  if (s.contains('cancel') || s.contains('closed') || s.contains('reject')) return false;
  return true;
}

List<ChatInboxItem> mergeChatInboxRooms({
  required String myId,
  required List<Map<String, dynamic>> orders,
  required List<Map<String, dynamic>> requests,
  required List<Map<String, dynamic>> messages,
  Map<String, List<String>> quoteChefIdsByRequest = const {},
}) {
  final catalog = <String, ChatInboxItem>{};

  for (final order in orders) {
    if (!orderChatIsActive(order)) continue;
    final roomId = orderChatRoomId(order);
    if (roomId.isEmpty) continue;
    final label = formatOrderId(order['order_id']?.toString() ?? order['id']?.toString(), roomId);
    final members = orderChatMemberIds(order).toList();
    final other = members.firstWhere((id) => id != myId, orElse: () => '');
    catalog[roomId] = ChatInboxItem(
      roomId: roomId,
      title: 'Order $label',
      preview: 'No messages yet. Open the Order# group.',
      memberIds: members,
      otherUserId: other.isEmpty ? null : other,
      lastAt: DateTime.tryParse(order['created_at']?.toString() ?? ''),
      isGroup: true,
    );
  }

  for (final request in requests) {
    if (!cateringChatIsActive(request)) continue;
    final roomId = request['id']?.toString() ?? '';
    if (roomId.isEmpty) continue;
    final members = cateringRequestChatMemberIds(
      request,
      quotingChefIds: quoteChefIdsByRequest[roomId] ?? const [],
    );
    final other = members.firstWhere((id) => id != myId, orElse: () => '');
    final title = request['title']?.toString().trim();
    catalog[roomId] = ChatInboxItem(
      roomId: roomId,
      title: (title == null || title.isEmpty) ? 'Catering lead' : title,
      preview: 'Catering chat. Message the other person here.',
      memberIds: members,
      otherUserId: other.isEmpty ? null : other,
      lastAt: DateTime.tryParse(request['created_at']?.toString() ?? ''),
      isGroup: members.length > 1,
    );
  }

  final latest = <String, Map<String, dynamic>>{};
  for (final message in messages) {
    final roomId = message['meal_id']?.toString() ?? '';
    if (roomId.isEmpty) continue;
    final at = DateTime.tryParse(message['created_at']?.toString() ?? '');
    final existing = latest[roomId];
    final existingAt = DateTime.tryParse(existing?['created_at']?.toString() ?? '');
    if (existing == null || (at != null && (existingAt == null || at.isAfter(existingAt)))) {
      latest[roomId] = message;
    }
  }

  final rooms = <String, ChatInboxItem>{};
  for (final entry in latest.entries) {
    final message = entry.value;
    final existing = catalog[entry.key];
    final preview = chatPreview(message['content']?.toString());
    if (existing == null) continue;
    rooms[entry.key] = ChatInboxItem(
      roomId: existing.roomId,
      title: existing.title,
      preview: preview,
      memberIds: existing.memberIds,
      otherUserId: existing.otherUserId,
      lastAt: DateTime.tryParse(message['created_at']?.toString() ?? '') ?? existing.lastAt,
      lastSenderId: message['sender_id']?.toString() ?? existing.lastSenderId,
      isGroup: existing.isGroup,
    );
  }

  final list = rooms.values.toList()
    ..sort((a, b) {
      final aAt = a.lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
  return list;
}

bool chatRoomHasUnread({
  required String myId,
  DateTime? lastAt,
  String? lastSenderId,
  DateTime? lastReadAt,
}) {
  if (lastAt == null) return false;
  if (lastSenderId != null && lastSenderId == myId) return false;
  if (lastReadAt == null) return true;
  return lastAt.isAfter(lastReadAt);
}

List<String> parseChatMemberIds(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(',')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
}

Set<String> orderChatMemberIds(Map<String, dynamic> order) {
  final ids = <String>{};
  for (final key in const [
    'customer_id',
    'user_id',
    'chef_id',
    'driver_id',
    'delivery_partner_id',
  ]) {
    final id = order[key]?.toString().trim() ?? '';
    if (id.isNotEmpty) ids.add(id);
  }
  return ids;
}

/// One room per order so customer, chef, and driver share the Order# group.
String orderChatRoomId(Map<String, dynamic> order, {List<Map<String, dynamic>>? items}) {
  return resolvedOrderId(order) ??
      (items != null && items.isNotEmpty ? resolvedOrderId(items.first) : null) ??
      '';
}

bool shouldNotifyChatMember({
  required String? myId,
  required String? senderId,
  Set<String>? memberIds,
}) {
  if (myId == null || myId.isEmpty || senderId == null || senderId.isEmpty || senderId == myId) {
    return false;
  }
  if (memberIds == null) return true;
  return memberIds.contains(myId);
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
  final dt = parseFlexibleDate(isoString);
  if (dt == null) return 'Unknown Time';
  return formatAppDateTime(dt);
}


/// Formats minutes-from-midnight as `h:mm AM/PM`.

String digitsOnlyPhone(String? raw) => (raw ?? '').replaceAll(RegExp(r'\D'), '');

/// 10-digit Indian mobile, or empty if the number is dummy / too short.
String usableCustomerPhone(String? raw) {
  var digits = digitsOnlyPhone(raw);
  if (digits.startsWith('91') && digits.length >= 12) {
    digits = digits.substring(digits.length - 10);
  } else if (digits.length > 10) {
    digits = digits.substring(digits.length - 10);
  }
  if (digits.length != 10) return '';
  if (isPlaceholderPhone(digits)) return '';
  if (!RegExp(r'^[6-9]').hasMatch(digits)) return '';
  return digits;
}

/// Dummy / repeated digits that should never be used as a diner contact.
bool isPlaceholderPhone(String? raw) {
  final digits = digitsOnlyPhone(raw);
  if (digits.isEmpty) return true;
  if (digits == '1234567890' || digits == '0123456789') return true;
  if (digits.length >= 10 && RegExp(r'^(\d)\1+$').hasMatch(digits)) return true;
  return false;
}

String e164IndiaPhone(String? raw) {
  final digits = usableCustomerPhone(raw);
  if (digits.isEmpty) return '';
  return '+91$digits';
}

/// True when the selected slot's start is now or earlier on that calendar day.


bool isFestivalHamper(Map<String, dynamic>? meal) {
  if (meal == null) return false;
  final flag = meal['is_hamper'] ?? meal['isHamper'];
  if (_explicitFalseFlag(flag)) return false;
  if (_truthyFlag(flag)) return true;
  final category = meal['category']?.toString().trim().toLowerCase() ?? '';
  final title = meal['title']?.toString().trim().toLowerCase() ?? '';
  final tags = '${meal['health_tags'] ?? meal['tags'] ?? ''}'.toLowerCase();
  return category.contains('hamper') ||
      category.contains('festival') ||
      title.contains('hamper') ||
      tags.contains('hamper');
}

List<Map<String, dynamic>> festivalHamperMeals(
  Iterable<Map<String, dynamic>> meals, {
  Set<String> excludedChefIds = const {},
  int limit = 8,
  double? destinationLat,
  double? destinationLng,
  Map<String, Map<String, dynamic>> chefKitchenPins = const {},
}) {
  final unique = <String>{};
  final hampers = <Map<String, dynamic>>[];
  for (final meal in meals) {
    if (!isFestivalHamper(meal)) continue;
    if (!isCatalogMeal(meal) || !isMealAvailableForCart(meal)) continue;
    final chefId = meal['chef_id']?.toString() ?? '';
    if (chefId.isNotEmpty && excludedChefIds.contains(chefId)) continue;
    final pinned = mealWithKitchenPin(meal, chefPin: chefKitchenPins[chefId]);
    if (!mealInDeliveryRadius(
      pinned,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
    )) {
      continue;
    }
    final id = meal['id']?.toString() ?? meal['title']?.toString() ?? '';
    if (id.isNotEmpty && !unique.add(id)) continue;
    hampers.add(pinned);
    if (hampers.length >= limit) break;
  }
  return hampers;
}

String festivalHamperHeadline(Map<String, dynamic> meal) {
  final code = PricingCalculator.mealPromoCode(meal);
  if (code != null) return 'Hamper · $code';
  return 'Festival hamper';
}

String festivalHamperSubhead(Map<String, dynamic> meal) {
  final title = mealDisplayTitle(meal, fallback: '');
  final chef = chefDisplayName(meal, fallback: '');
  if (title.isNotEmpty && chef.isNotEmpty) return '$title · $chef';
  if (title.isNotEmpty) return title;
  return 'Gift a home kitchen box';
}

bool _truthyFlag(dynamic flag) {
  if (flag == true) return true;
  if (flag == false || flag == null) return false;
  final text = flag.toString().toLowerCase().trim();
  return text == 'true' || text == '1' || text == 'yes';
}

bool _explicitFalseFlag(dynamic flag) {
  if (flag == false) return true;
  if (flag == null) return false;
  final text = flag.toString().toLowerCase().trim();
  return text == 'false' || text == '0' || text == 'no';
}

bool isSocietyNight(Map<String, dynamic>? meal) {
  if (meal == null) return false;
  final flag = meal['is_society_night'] ?? meal['isSocietyNight'];
  if (_explicitFalseFlag(flag)) return false;
  if (_truthyFlag(flag)) return true;
  final category = meal['category']?.toString().trim().toLowerCase() ?? '';
  final title = meal['title']?.toString().trim().toLowerCase() ?? '';
  final label = meal['society_label']?.toString().trim() ?? '';
  return category.contains('society') ||
      category.contains('rwa') ||
      title.contains('society night') ||
      label.isNotEmpty && category.contains('community');
}

String societyNightLabel(Map<String, dynamic>? meal) {
  final label = meal?['society_label']?.toString().trim() ?? '';
  if (label.isNotEmpty) return label;
  return 'Society night';
}

bool societyLabelMatchesAddress(String? societyLabel, Map<String, dynamic>? address) {
  final label = normalizeAddressKey(societyLabel ?? '');
  if (label.isEmpty) return true;
  if (address == null) return false;
  final haystack = normalizeAddressKey([
    address['society_name'],
    address['wing'],
    address['flat_no'],
    address['house_no'],
    address['landmark'],
    address['street'],
    address['address_line1'],
    address['city'],
    address['address'],
  ].where((v) => v != null && v.toString().trim().isNotEmpty).join(' '));
  if (haystack.isEmpty) return false;
  if (haystack.contains(label) || label.contains(haystack)) return true;
  final tokens = label.split(RegExp(r'\s+')).where((t) => t.length >= 3).toList();
  if (tokens.isEmpty) return haystack.contains(label);
  return tokens.every(haystack.contains);
}

List<Map<String, dynamic>> societyNightMeals(
  Iterable<Map<String, dynamic>> meals, {
  Set<String> excludedChefIds = const {},
  int limit = 8,
  double? destinationLat,
  double? destinationLng,
  Map<String, dynamic>? destinationAddress,
  Map<String, Map<String, dynamic>> chefKitchenPins = const {},
}) {
  final unique = <String>{};
  final nights = <Map<String, dynamic>>[];
  for (final meal in meals) {
    if (!isSocietyNight(meal)) continue;
    if (!isCatalogMeal(meal) || !isMealAvailableForCart(meal)) continue;
    final chefId = meal['chef_id']?.toString() ?? '';
    if (chefId.isNotEmpty && excludedChefIds.contains(chefId)) continue;
    final societyLabel = meal['society_label']?.toString();
    if (destinationAddress != null &&
        (societyLabel ?? '').trim().isNotEmpty &&
        !societyLabelMatchesAddress(societyLabel, destinationAddress)) {
      continue;
    }
    final pinned = mealWithKitchenPin(meal, chefPin: chefKitchenPins[chefId]);
    if (!mealInDeliveryRadius(
      pinned,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
    )) {
      continue;
    }
    final id = meal['id']?.toString() ?? meal['title']?.toString() ?? '';
    if (id.isNotEmpty && !unique.add(id)) continue;
    nights.add(pinned);
    if (nights.length >= limit) break;
  }
  return nights;
}

String societyNightHeadline(Map<String, dynamic> meal) {
  return societyNightLabel(meal);
}

String societyNightSubhead(Map<String, dynamic> meal) {
  final title = mealDisplayTitle(meal, fallback: '');
  final chef = chefDisplayName(meal, fallback: '');
  final slot = formatDeliverySlotLabel(meal);
  final parts = <String>[
    if (title.isNotEmpty) title,
    if (chef.isNotEmpty) chef,
    if (slot.isNotEmpty && slot != 'ASAP') slot,
  ];
  if (parts.isEmpty) return 'One building · one kitchen · one drop';
  return parts.join(' · ');
}

bool isShelfItem(Map<String, dynamic>? meal) {
  if (meal == null) return false;
  final flag = meal['is_shelf_item'] ?? meal['isShelfItem'];
  if (_explicitFalseFlag(flag)) return false;
  if (_truthyFlag(flag)) return true;
  final category = meal['category']?.toString().trim().toLowerCase() ?? '';
  final title = meal['title']?.toString().trim().toLowerCase() ?? '';
  final kind = meal['shelf_kind']?.toString().trim().toLowerCase() ?? '';
  final tags = '${meal['health_tags'] ?? meal['tags'] ?? ''}'.toLowerCase();
  return category.contains('shelf') ||
      category.contains('pantry') ||
      kind.isNotEmpty ||
      title.contains('pickle') ||
      title.contains('papad') ||
      title.contains('chutney jar') ||
      tags.contains('shelf') ||
      tags.contains('pantry');
}

String shelfItemKind(Map<String, dynamic>? meal) {
  final kind = meal?['shelf_kind']?.toString().trim() ?? '';
  if (kind.isNotEmpty) return kind;
  final category = meal?['category']?.toString().trim() ?? '';
  if (category.toLowerCase().contains('shelf') ||
      category.toLowerCase().contains('pantry')) {
    return category;
  }
  return 'Shelf from home';
}

List<Map<String, dynamic>> shelfItems(
  Iterable<Map<String, dynamic>> meals, {
  Set<String> excludedChefIds = const {},
  int limit = 8,
  double? destinationLat,
  double? destinationLng,
  Map<String, Map<String, dynamic>> chefKitchenPins = const {},
}) {
  final unique = <String>{};
  final items = <Map<String, dynamic>>[];
  for (final meal in meals) {
    if (!isShelfItem(meal)) continue;
    if (!isCatalogMeal(meal) || !isMealAvailableForCart(meal)) continue;
    final chefId = meal['chef_id']?.toString() ?? '';
    if (chefId.isNotEmpty && excludedChefIds.contains(chefId)) continue;
    final pinned = mealWithKitchenPin(meal, chefPin: chefKitchenPins[chefId]);
    if (!mealInDeliveryRadius(
      pinned,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
    )) {
      continue;
    }
    final id = meal['id']?.toString() ?? meal['title']?.toString() ?? '';
    if (id.isNotEmpty && !unique.add(id)) continue;
    items.add(pinned);
    if (items.length >= limit) break;
  }
  return items;
}

String shelfItemHeadline(Map<String, dynamic> meal) {
  return shelfItemKind(meal);
}

String shelfItemSubhead(Map<String, dynamic> meal) {
  final title = mealDisplayTitle(meal, fallback: '');
  final chef = chefDisplayName(meal, fallback: '');
  if (title.isNotEmpty && chef.isNotEmpty) return '$title · $chef';
  if (title.isNotEmpty) return title;
  return 'Pickle, masala & pantry from home kitchens';
}

bool orderLineIsRescuePlate(Map<String, dynamic> item) {
  final type = (item['offer_type'] ??
          item['offerType'] ??
          (item['rawMealDetails'] is Map ? item['rawMealDetails']['offer_type'] : null) ??
          (item['mealDetails'] is Map ? item['mealDetails']['offer_type'] : null) ??
          (item['meal_details'] is Map ? item['meal_details']['offer_type'] : null) ??
          '')
      .toString()
      .toLowerCase();
  return type.contains('flash');
}

/// True when the line/order asks for a clock slot (not ASAP) — chef cooks to that demand.
bool orderIsPreOrderSlot(Map<String, dynamic> orderOrItem) {
  final fields = orderSlotFields(orderOrItem);
  if (isImmediateDeliverySlot(fields['time_slot']?.toString())) return false;
  final selectedDate = fields['selected_date']?.toString().trim() ?? '';
  if (selectedDate.isNotEmpty) return true;
  return (fields['time_slot']?.toString().trim() ?? '').isNotEmpty;
}

int preOrderedPlatesFromOrderItems(Iterable<dynamic> items) {
  var total = 0;
  for (final raw in items) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    if (!orderIsPreOrderSlot(item)) continue;
    final qty = int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
    total += qty < 1 ? 1 : qty;
  }
  return total;
}

int preOrderedPlatesFromOrders(Iterable<dynamic> orders) {
  var total = 0;
  for (final row in orders) {
    if (row is! Map) continue;
    if (!referralOrderCountsTowardBonus(row['status']?.toString())) continue;
    final order = Map<String, dynamic>.from(row);
    final items = parseOrderItemsList(order['items'] ?? order['cart_items'] ?? order['order_items']);
    if (items.isEmpty) {
      if (orderIsPreOrderSlot(order)) total += 1;
      continue;
    }
    // Prefer line-level slots; if lines omit slot, fall back to order-level.
    final fromLines = preOrderedPlatesFromOrderItems(items);
    if (fromLines > 0) {
      total += fromLines;
    } else if (orderIsPreOrderSlot(order)) {
      for (final item in items) {
        final qty = int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
        total += qty < 1 ? 1 : qty;
      }
    }
  }
  return total;
}

int rescuedPlatesFromOrderItems(Iterable<dynamic> items) =>
    preOrderedPlatesFromOrderItems(items);

int rescuedPlatesFromOrders(Iterable<dynamic> orders) =>
    preOrderedPlatesFromOrders(orders);


bool isSoldOutCheckoutError(Object? error, [Map<String, dynamic>? data]) {
  if (data?['code']?.toString() == 'sold_out') return true;
  final text = '${data?['error'] ?? error}'.toLowerCase();
  return text.contains('sold out') || text.contains('no longer available');
}

bool isKitchenClosedCheckoutError(Object? error, [Map<String, dynamic>? data]) {
  if (data?['code']?.toString() == 'kitchen_closed') return true;
  final text = '${data?['error'] ?? error}'.toLowerCase();
  return text.contains('kitchen_closed') ||
      text.contains('kitchen is closed') ||
      text.contains('kitchen just went offline');
}

String kitchenClosedCheckoutMessage({required bool charged, bool refunded = false}) {
  if (charged && refunded) {
    return 'This kitchen just went offline. ${dinerRefundMoneyCopy(refunded: true)}';
  }
  if (charged) {
    return 'This kitchen just went offline after payment. ${dinerRefundMoneyCopy(refunded: false)}';
  }
  return 'This kitchen is closed right now. Nothing was charged — try another chef or wait until they go online.';
}

String checkoutInitErrorMessage(Object? error, [Map<String, dynamic>? data]) {
  if (isSoldOutCheckoutError(error, data)) return soldOutCheckoutMessage(charged: false);
  if (isKitchenClosedCheckoutError(error, data)) {
    return kitchenClosedCheckoutMessage(charged: false);
  }
  return 'Initialization Failed: ${networkErrorMessage(error)}';
}

String chefPayoutStatusLabel(String? status) {
  switch ((status ?? '').toLowerCase().trim()) {
    case 'released':
      return 'Payout released';
    case 'awaiting_account':
      return 'Waiting for your bank account';
    case 'failed':
      return 'Payout failed — we will retry';
    case 'recorded':
      return 'Payout recorded';
    case 'processing':
      return 'Payout processing';
    case 'not_applicable':
      return 'No payout on this order';
    case 'pending':
    case '':
      return 'Payout pending';
    default:
      return 'Payout: $status';
  }
}

List<Map<String, dynamic>> uniqueReviewableOrderItems(List<Map<String, dynamic>> items) {
  final seen = <String>{};
  final unique = <Map<String, dynamic>>[];
  for (final item in items) {
    final id = mealIdFromOrderItem(item) ?? item['title']?.toString() ?? '';
    final key = id.isEmpty ? 'line-${unique.length}' : id;
    if (!seen.add(key)) continue;
    unique.add(item);
  }
  return unique;
}

/// Only the review written for this order. Never reuse a rating from another order
/// of the same plate, or a row that stored the meal id as `order_id`.
Map<String, Map<String, dynamic>> reviewsForOrderMeals({
  required Iterable<Map<String, dynamic>> rows,
  required String? orderId,
}) {
  final want = (orderId ?? '').trim();
  final keyed = <String, Map<String, dynamic>>{};
  if (want.isEmpty) return keyed;
  for (final row in rows) {
    final rowOrder = row['order_id']?.toString().trim() ?? '';
    if (rowOrder != want) continue;
    final mealId = row['meal_id']?.toString().trim() ?? '';
    if (mealId.isEmpty) continue;
    keyed[mealId] = row;
  }
  return keyed;
}

String soldOutCheckoutMessage({required bool charged, bool refunded = false}) {
  if (charged && refunded) {
    return 'This meal just sold out. ${dinerRefundMoneyCopy(refunded: true)}';
  }
  if (charged) {
    return 'This meal just sold out after payment. ${dinerRefundMoneyCopy(refunded: false)}';
  }
  return 'This meal just sold out. Nothing was charged — pick another portion or chef.';
}

String checkoutErrorMessage(Object error) {
  final networked = networkErrorMessage(error).trim();
  if (!isGenericNetworkFallback(networked)) return networked;
  var text = error.toString().trim();
  if (text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length).trim();
  }
  if (text.isEmpty) return networked;
  return text;
}

/// Prefer the edge-function `error` field over raw FunctionsHttpException text.
String boostPaymentErrorMessage(Object error) {
  try {
    final details = (error as dynamic).details;
    if (details is Map && details['error'] != null) {
      return details['error'].toString();
    }
  } catch (_) {}
  final raw = error.toString();
  final match = RegExp(r'error:\s*([^}\]]+)').firstMatch(raw);
  if (match != null) {
    final extracted = match.group(1)?.trim() ?? '';
    if (extracted.isNotEmpty && !extracted.toLowerCase().startsWith('false')) {
      return extracted.replaceAll(RegExp(r'[,\s]+$'), '');
    }
  }
  return checkoutErrorMessage(error);
}

dynamic _jsonSafeValue(dynamic value) {
  if (value == null || value is num || value is bool) return value;
  if (value is String) return value;
  if (value is DateTime) return value.toIso8601String();
  if (value is List) return value.map(_jsonSafeValue).toList();
  if (value is Map) {
    return value.map((key, nested) => MapEntry(key.toString(), _jsonSafeValue(nested)));
  }
  return value.toString();
}

String? _chefScheduleFromLine(Map<String, dynamic> item, Map<String, dynamic> nestedMap) {
  for (final raw in [
    item['chef_schedule'],
    nestedMap['chef_schedule'],
    nestedMap['time_slot'],
  ]) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty || isImmediateDeliverySlot(text)) continue;
    return text;
  }
  return null;
}

String? _nextBookableChefHour(String? chefSchedule, Map<String, dynamic> item) {
  final chef = (chefSchedule ?? '').trim();
  if (chef.isEmpty || isImmediateDeliverySlot(chef)) return null;
  final dateRaw = item['selected_date'] ?? item['selectedDate'] ?? item['scheduled_date'] ?? item['scheduledDate'];
  final scheduled = dateRaw is DateTime
      ? dateRaw
      : (parseFlexibleDate(dateRaw?.toString()) ?? DateTime.now());
  final future = futureChefSubSlots(chef, scheduledDate: scheduled);
  if (future.isNotEmpty) return future.first;
  final hours = chefHourlySubSlots(chef);
  return hours.isEmpty ? null : hours.first;
}

String? _dinerTimeSlotForCheckoutLine(Map<String, dynamic> item, Map<String, dynamic> nestedMap) {
  final chef = _chefScheduleFromLine(item, nestedMap);
  final picked = preferredDinerTimeSlot([
    item['exact_time'],
    item['timeSlot'],
    item['time_slot'],
    nestedMap['exact_time'],
    nestedMap['time_slot'],
    chef,
  ], fallback: '');
  if (!isImmediateDeliverySlot(picked) && picked.isNotEmpty && !looksLikeChefServingWindow(picked)) {
    return picked;
  }
  return _nextBookableChefHour(chef, item) ??
      (picked.isEmpty || isImmediateDeliverySlot(picked) ? null : picked);
}

/// Keeps only JSON-safe checkout fields so paid-order recording cannot fail on meal blobs.
List<Map<String, dynamic>> checkoutCartPayload(
  List<Map<String, dynamic>> items, {
  String? appliedPromoCode,
}) {
  return items.map((item) {
    final nested = item['rawMealDetails'] ??
        item['mealDetails'] ??
        item['meal_details'] ??
        const <String, dynamic>{};
    final nestedMap = nested is Map ? Map<String, dynamic>.from(nested) : const <String, dynamic>{};
    final chefId = item['chef_id'] ?? item['chefId'] ?? nestedMap['chef_id'] ?? nestedMap['chefId'];
    final mealId = item['source_meal_id'] ??
        item['meal_id'] ??
        item['mealId'] ??
        nestedMap['id'] ??
        nestedMap['meal_id'];
    final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
    final addOns = item['selectedAddOns'] ?? item['selected_add_ons'] ?? const [];
    final snapshot = PricingCalculator.snapshotCheckoutPrices(
      PricingCalculator.pricingSourceFromLine({
        ...item,
        'rawMealDetails': nestedMap,
      }),
      qty,
      appliedPromoCode: appliedPromoCode,
      addOnsUnit: PricingCalculator.addOnsTotal(addOns),
    );
    return {
      'chef_id': chefId,
      'chefId': chefId,
      'chef_name': chefDisplayName({...nestedMap, ...item}),
      'meal_id': mealId,
      'source_meal_id': mealId,
      'title': item['title'] ?? item['name'] ?? nestedMap['title'],
      'quantity': qty,
      'price': snapshot['price'],
      'base_price': snapshot['base_price'],
      'discounted_price': snapshot['discounted_price'],
      'offer_type': snapshot['offer_type'],
      'discount_value': snapshot['discount_value'],
      'max_discount_cap': snapshot['max_discount_cap'],
      'offer_valid_until': snapshot['offer_valid_until'],
      'offer_valid_from': snapshot['offer_valid_from'],
      'line_gross': snapshot['line_gross'],
      'line_net': snapshot['line_net'],
      'offer_applied': snapshot['offer_applied'],
      'offer_description': snapshot['offer_description'],
      'promo_code': snapshot['promo_code'],
      'promo_discount_type': snapshot['promo_discount_type'],
      'promo_discount_value': snapshot['promo_discount_value'],
      'applied_promo_code': snapshot['applied_promo_code'],
      'promo_applied': snapshot['promo_applied'],
      'meal_unit': snapshot['meal_unit'],
      'addons_unit': snapshot['addons_unit'],
      'selected_service_type': item['selected_service_type'] ?? item['service_type'] ?? item['serviceType'],
      'service_type': item['service_type'] ?? item['selected_service_type'] ?? item['serviceType'],
      'exact_time': _dinerTimeSlotForCheckoutLine(item, nestedMap),
      'time_slot': _dinerTimeSlotForCheckoutLine(item, nestedMap),
      'chef_schedule': nestedMap['time_slot'] ?? nestedMap['chef_schedule'],
      ...storedSlotDateFields(item),
      'selectedAddOns': _jsonSafeValue(item['selectedAddOns'] ?? item['selected_add_ons'] ?? const []),
      'accepts_hotpot_coins': item['accepts_hotpot_coins'] ?? nestedMap['accepts_hotpot_coins'],
      'specialInstructions': item['specialInstructions'] ?? item['special_instructions'],
      'special_instructions': item['specialInstructions'] ?? item['special_instructions'],
      // Keep specialty meal identity through place_customer_order → chef/driver/invoice.
      'is_hamper': nestedMap['is_hamper'] ?? item['is_hamper'] ?? item['isHamper'],
      'is_society_night':
          nestedMap['is_society_night'] ?? item['is_society_night'] ?? item['isSocietyNight'],
      'society_label': nestedMap['society_label'] ?? item['society_label'] ?? item['societyLabel'],
      'is_shelf_item': nestedMap['is_shelf_item'] ?? item['is_shelf_item'] ?? item['isShelfItem'],
      'shelf_kind': nestedMap['shelf_kind'] ?? item['shelf_kind'] ?? item['shelfKind'],
      if (nestedMap.isNotEmpty ||
          item['is_hamper'] != null ||
          item['is_society_night'] != null ||
          item['society_label'] != null ||
          item['is_shelf_item'] != null ||
          item['shelf_kind'] != null)
        'rawMealDetails': {
          ...nestedMap,
          if (nestedMap['is_hamper'] != null || item['is_hamper'] != null)
            'is_hamper': nestedMap['is_hamper'] ?? item['is_hamper'] ?? item['isHamper'],
          if (nestedMap['is_society_night'] != null || item['is_society_night'] != null)
            'is_society_night':
                nestedMap['is_society_night'] ?? item['is_society_night'] ?? item['isSocietyNight'],
          if ((nestedMap['society_label'] ?? item['society_label']) != null)
            'society_label': nestedMap['society_label'] ?? item['society_label'] ?? item['societyLabel'],
          if (nestedMap['is_shelf_item'] != null || item['is_shelf_item'] != null)
            'is_shelf_item': nestedMap['is_shelf_item'] ?? item['is_shelf_item'] ?? item['isShelfItem'],
          if ((nestedMap['shelf_kind'] ?? item['shelf_kind']) != null)
            'shelf_kind': nestedMap['shelf_kind'] ?? item['shelf_kind'] ?? item['shelfKind'],
        },
    };
  }).toList();
}

double parseMoney(dynamic value, [double fallback = 0]) {
  return tryParseMoney(value) ?? fallback;
}

double? tryParseMoney(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

double packagingOrderTotal(double unitPrice, int quantity) {
  final qty = quantity < 1 ? 1 : quantity;
  final unit = unitPrice < 0 ? 0.0 : unitPrice;
  return PricingCalculator.roundCurrency(unit * qty);
}

final _supplyRequestIdPattern = RegExp(r'\bSUP-[A-Z0-9]+\b', caseSensitive: false);

bool isPackagingSupplyRequest(Map<String, dynamic>? request) {
  if (request == null) return false;
  final type = '${request['request_type'] ?? ''} ${request['service_type'] ?? ''}'.toLowerCase();
  if (type.contains('packaging') || type.contains('supply')) return true;
  return _supplyRequestIdPattern.hasMatch('${request['description'] ?? ''} ${request['title'] ?? ''}');
}

bool isOpenPackagingSupplyRequest(Map<String, dynamic>? request) {
  if (!isPackagingSupplyRequest(request)) return false;
  final status = request?['status']?.toString().toLowerCase().trim() ?? '';
  if (status.contains('cancel') ||
      status.contains('close') ||
      status.contains('reject') ||
      status.contains('fulfill') ||
      status.contains('fulfilled') ||
      status == 'completed' ||
      status.contains('completed')) {
    return false;
  }
  return true;
}

bool packagingCatalogItemRequested(
  Iterable<Map<String, dynamic>> requests,
  Map<String, dynamic> item,
) {
  final title = item['title']?.toString().trim().toLowerCase() ?? '';
  final sku = (item['sku'] ?? item['id'])?.toString().trim() ?? '';
  for (final request in requests) {
    if (!isOpenPackagingSupplyRequest(request)) continue;
    final requestTitle = request['title']?.toString().trim().toLowerCase() ?? '';
    if (title.isNotEmpty && requestTitle == title) return true;
    if (sku.isNotEmpty) {
      final desc = request['description']?.toString() ?? '';
      if (desc.contains('SKU $sku') || RegExp('\\bSKU\\s+$sku\\b', caseSensitive: false).hasMatch(desc)) {
        return true;
      }
    }
  }
  return false;
}

String packagingRequestDisplayId(Map<String, dynamic> request) {
  final explicit = request['request_id']?.toString().trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  return _supplyRequestIdPattern.firstMatch('${request['description'] ?? ''}')?.group(0) ?? '';
}

Map<String, dynamic> packagingSupplyRequestPayload({
  required String chefId,
  required String chefName,
  required String chefEmail,
  required String chefPhone,
  required String kitchenAddress,
  required String title,
  required String requestId,
  required String sku,
  required String description,
  required int quantity,
  required double unitPrice,
}) {
  final qty = quantity < 1 ? 1 : quantity;
  final total = packagingOrderTotal(unitPrice, qty);
  return {
    'customer_id': chefId,
    'customer_name': chefName,
    'customer_email': chefEmail,
    'customer_phone': chefPhone,
    'title': title,
    'description': [
      if (requestId.trim().isNotEmpty) 'Request $requestId',
      if (sku.trim().isNotEmpty) 'SKU $sku',
      if (description.trim().isNotEmpty) description.trim(),
    ].join('\n'),
    'quantity': qty,
    'remaining_quantity': qty,
    'budget': total,
    'quoted_total': total,
    'service_type': 'Packaging',
    'request_type': 'packaging',
    'delivery_address': kitchenAddress,
    'target_date_time': DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String(),
    'status': 'Open',
    'created_at': DateTime.now().toIso8601String(),
  };
}

const double kDefaultPackagingFee = 20;
const double kDefaultDeliveryEstimate = 30;
const double kDefaultDriverPayout = 40;

double packagingFeeForLoyaltyTier(String? tier) {
  // Packaging is a disclosed per-order charge, not a loyalty perk.
  return kPackagingFeeAtFreeDelivery;
}

bool loyaltyTierIsGold(String? tier) => (tier ?? '').toLowerCase().contains('gold');

String formatRupees(num amount, {int fractionDigits = 2}) {
  return '₹${roundMoney(amount.toDouble()).toStringAsFixed(fractionDigits)}';
}

/// Whole rupees shown on a dish card, the dish page, and the Pay button.
int wholeRupees(num amount) => int.parse(amount.toStringAsFixed(0));

String packagingFeeLineLabel({required double fee, String? loyaltyTier}) {
  if (fee <= 0) return 'Packaging';
  if (fee <= kPackagingFeeBelowFreeDelivery) return 'Packaging (under ₹199)';
  return 'Packaging (₹199+)';
}

/// Per order: ₹10 when food is under ₹199, ₹20 at/above ₹199. Empty cart is ₹0.
double packagingFeeForCartItems(
  Iterable<Map<String, dynamic>> items, {
  String? loyaltyTier,
  double? loyaltyTierFee,
  double? foodTotal,
}) {
  final list = items.toList();
  if (list.isEmpty) return 0;
  var food = foodTotal ?? 0;
  if (foodTotal == null) {
    food = 0;
    for (final item in list) {
      final qty = (item['quantity'] as num?)?.toDouble() ??
          double.tryParse(item['quantity']?.toString() ?? '') ??
          1;
      final unit = (item['discounted_price'] as num?)?.toDouble() ??
          double.tryParse(item['discounted_price']?.toString() ?? '') ??
          (item['price'] as num?)?.toDouble() ??
          double.tryParse(item['price']?.toString() ?? '') ??
          (item['base_price'] as num?)?.toDouble() ??
          double.tryParse(item['base_price']?.toString() ?? '') ??
          0;
      food += unit * (qty <= 0 ? 1 : qty);
    }
  }
  if (food >= kFreeDeliveryMinFood) return kPackagingFeeAtFreeDelivery;
  return kPackagingFeeBelowFreeDelivery;
}

DateTime istCalendarDate([DateTime? now]) {
  final utc = (now ?? DateTime.now()).toUtc();
  final ist = utc.add(const Duration(hours: 5, minutes: 30));
  return DateTime(ist.year, ist.month, ist.day);
}

bool claimedStreakOnIstDate(String? lastCheckInDate, {DateTime? now}) {
  if (lastCheckInDate == null || lastCheckInDate.trim().isEmpty) return false;
  final parsed = DateTime.tryParse(lastCheckInDate.trim());
  if (parsed == null) return false;
  final last = DateTime(parsed.year, parsed.month, parsed.day);
  return last == istCalendarDate(now);
}

String? orderLineSpecialtyTag(Map<String, dynamic>? item) {
  if (item == null) return null;
  if (isFestivalHamper(item)) return 'Hamper';
  if (isSocietyNight(item)) return societyNightLabel(item);
  if (isShelfItem(item)) return shelfItemKind(item);
  return null;
}

String societyGroupCheckoutNote({
  String? placeKind,
  String? placeLabel,
  String? dropoffNote,
  String? timeSlot,
  String? roomCode,
}) {
  final parts = <String>[
    if ((placeKind ?? '').trim().isNotEmpty || (placeLabel ?? '').trim().isNotEmpty)
      'Group ${groupPlaceKindLabel(placeKind)}'
          '${(placeLabel ?? '').trim().isEmpty ? '' : ': ${placeLabel!.trim()}'}',
    if ((dropoffNote ?? '').trim().isNotEmpty) 'Drop: ${dropoffNote!.trim()}',
    if ((timeSlot ?? '').trim().isNotEmpty) 'Shared slot: ${timeSlot!.trim()}',
    if ((roomCode ?? '').trim().isNotEmpty) 'Room: ${roomCode!.trim().toUpperCase()}',
  ];
  if (parts.isEmpty) return '';
  return parts.join(' · ');
}

String mergedOrderInstructions(
  List<Map<String, dynamic>> items, [
  String? checkoutNote,
  Map<String, String?>? societyGroup,
]) {
  final notes = <String>[];
  if (societyGroup != null) {
    final groupNote = societyGroupCheckoutNote(
      placeKind: societyGroup['placeKind'] ?? societyGroup['place_kind'],
      placeLabel: societyGroup['placeLabel'] ?? societyGroup['place_label'],
      dropoffNote: societyGroup['dropoffNote'] ?? societyGroup['dropoff_note'],
      timeSlot: societyGroup['timeSlot'] ?? societyGroup['time_slot'],
      roomCode: societyGroup['roomCode'] ?? societyGroup['room_code'],
    );
    if (groupNote.isNotEmpty) notes.add(groupNote);
  }
  for (final item in items) {
    final note = (item['specialInstructions'] ?? item['special_instructions'] ?? '').toString().trim();
    if (note.isEmpty) continue;
    final title = (item['title'] ?? item['name'] ?? 'Item').toString().trim();
    notes.add(title.isEmpty ? note : '$title: $note');
  }
  final extra = checkoutNote?.trim() ?? '';
  if (extra.isNotEmpty && !notes.contains(extra)) notes.add(extra);
  return notes.join('\n');
}

double cateringPayableTotal(Map<String, dynamic> request) {
  final quoted = parseMoney(request['quoted_total'] ?? request['quoted_price']);
  if (quoted > 0) return quoted;
  return parseMoney(request['budget']);
}

/// Open + selected bids for a catering request, cheapest first.
List<Map<String, dynamic>> cateringQuotesSorted(Iterable<dynamic> rows) {
  final quotes = rows
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((q) {
        final status = q['status']?.toString().toLowerCase().trim() ?? 'open';
        return status == 'open' || status == 'selected';
      })
      .toList();
  quotes.sort((a, b) {
    final selectedA = a['status']?.toString().toLowerCase() == 'selected' ? 0 : 1;
    final selectedB = b['status']?.toString().toLowerCase() == 'selected' ? 0 : 1;
    if (selectedA != selectedB) return selectedA.compareTo(selectedB);
    final priceCmp = parseMoney(a['quoted_total']).compareTo(parseMoney(b['quoted_total']));
    if (priceCmp != 0) return priceCmp;
    return (a['created_at']?.toString() ?? '').compareTo(b['created_at']?.toString() ?? '');
  });
  return quotes;
}

String cateringQuoteChefLabel(Map<String, dynamic> quote) {
  final name = quote['chef_name']?.toString().trim() ?? '';
  if (name.isNotEmpty) return name;
  final id = quote['chef_id']?.toString() ?? '';
  if (id.length >= 8) return 'Kitchen ${id.substring(0, 8).toUpperCase()}';
  return 'Kitchen';
}

bool mealAcceptsHotpotCoins(Map<String, dynamic> meal) {
  final flag = meal['accepts_hotpot_coins'] ??
      (meal['rawMealDetails'] is Map ? meal['rawMealDetails']['accepts_hotpot_coins'] : null) ??
      (meal['meal_details'] is Map ? meal['meal_details']['accepts_hotpot_coins'] : null);
  if (flag == false || flag?.toString() == 'false') return false;
  return true;
}

bool cartAcceptsHotpotCoins(Iterable<Map<String, dynamic>> items) =>
    items.every(mealAcceptsHotpotCoins);

String? dietSkipReason(
  Map<String, dynamic> meal, {
  String? preference,
  String? allergies,
  String? title,
}) {
  if (mealMatchesCustomerDiet(meal, preference: preference, allergies: allergies)) {
    return null;
  }
  final name = (title ?? meal['title'] ?? meal['name'] ?? 'This dish').toString();
  if (!mealAvoidsAllergies(meal, allergies)) {
    return '$name may contain an allergen you listed';
  }
  return '$name does not match your dietary preference';
}

/// Partner payout for a run. A stored 0 is treated as missing, not as "earned nothing".
double driverPayoutFromOrder(Map<String, dynamic> order) {
  final tip = parseMoney(order['tip_amount'] ?? order['tip']);
  final fee = parseMoney(order['delivery_fee']);
  final explicit = parseMoney(order['driver_payout'] ?? order['payout']);
  if (explicit > 0) {
    // Fee-only stored payouts still need the customer tip added.
    if (tip > 0 && fee > 0 && (explicit - fee).abs() < 0.01) {
      return explicit + tip;
    }
    return explicit;
  }
  if (fee > 0) return fee + tip;
  return kDefaultDriverPayout + tip;
}

double fleetEarningsFrom({
  double wallet = 0,
  double lifetime = 0,
  Iterable<double> deliveryPayouts = const [],
}) {
  if (lifetime > 0) return lifetime;
  if (wallet > 0) return wallet;
  return deliveryPayouts.fold<double>(0, (sum, payout) => sum + payout);
}

/// Compact dish list for driver cards (e.g. "2 items · Dal · Rice").
String driverOrderItemsSummary(Iterable<Map<String, dynamic>> items, {int maxTitles = 2}) {
  final titles = <String>[];
  var totalQty = 0;
  for (final item in items) {
    final rawQty = int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
    totalQty += rawQty < 1 ? 1 : rawQty;
    final title = (item['title'] ?? item['name'] ?? item['meal_name'])?.toString().trim() ?? '';
    if (title.isEmpty) continue;
    if (titles.length < maxTitles && !titles.any((t) => t.toLowerCase() == title.toLowerCase())) {
      titles.add(title);
    }
  }
  if (totalQty <= 0) totalQty = titles.isEmpty ? 0 : titles.length;
  if (titles.isEmpty) {
    if (totalQty <= 0) return '';
    return totalQty == 1 ? '1 item' : '$totalQty items';
  }
  final joined = titles.join(' · ');
  final hasMoreDishes = items.length > titles.length;
  if (totalQty <= 1 && !hasMoreDishes) return joined;
  return hasMoreDishes ? '$totalQty items · $joined…' : '$totalQty items · $joined';
}

/// Short dropoff snippet for driver history rows.
String briefDriverAddress(String? address, {int maxChars = 40}) {
  final cleaned = (address ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return '';
  final lower = cleaned.toLowerCase();
  if (lower.contains('pending') || lower == 'n/a') return '';
  if (cleaned.length <= maxChars) return cleaned;
  return '${cleaned.substring(0, maxChars - 1)}…';
}

double roundMoney(double value) => (value * 100).round() / 100;

/// Platform take on food + packaging. Delivery fee stays with the platform.
const double kPlatformMarginRate = 0.15;

const Set<String> _placeholderChefNames = {
  'home chef',
  'home kitchen',
  'home cook',
  'chef kitchen',
  'chef',
  'chef name',
};

bool isPlaceholderChefName(String? name) {
  final value = name?.trim().toLowerCase() ?? '';
  return value.isEmpty || _placeholderChefNames.contains(value);
}

/// Prefers the chef profile display name, then kitchen name, then the email local-part.
String chefDisplayName(Map<String, dynamic>? data, {String fallback = 'Home Kitchen'}) {
  if (data == null) return fallback;
  for (final key in const [
    'chef_name',
    'kitchen_name',
    'name',
    'full_name',
    'display_name',
    'accepted_chef_name',
  ]) {
    final value = data[key]?.toString().trim() ?? '';
    if (!isPlaceholderChefName(value)) return value;
  }
  final email = data['email']?.toString() ?? '';
  final at = email.indexOf('@');
  if (at > 0) {
    final local = email.substring(0, at).trim();
    if (local.isNotEmpty) return local;
  }
  return fallback;
}

enum ChefSocialPlatform { instagram, youtube, facebook }

class ChefSocialLinks {
  const ChefSocialLinks({
    this.instagramUrl = '',
    this.youtubeUrl = '',
    this.facebookUrl = '',
  });

  final String instagramUrl;
  final String youtubeUrl;
  final String facebookUrl;

  bool get hasAny =>
      instagramUrl.isNotEmpty || youtubeUrl.isNotEmpty || facebookUrl.isNotEmpty;

  factory ChefSocialLinks.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const ChefSocialLinks();
    return ChefSocialLinks(
      instagramUrl: sanitizeChefSocialUrl(data['instagram_url']?.toString(), ChefSocialPlatform.instagram) ?? '',
      youtubeUrl: sanitizeChefSocialUrl(data['youtube_url']?.toString(), ChefSocialPlatform.youtube) ?? '',
      facebookUrl: sanitizeChefSocialUrl(data['facebook_url']?.toString(), ChefSocialPlatform.facebook) ?? '',
    );
  }

  String get platformsLabel {
    final names = <String>[
      if (youtubeUrl.isNotEmpty) 'YouTube',
      if (instagramUrl.isNotEmpty) 'Instagram',
      if (facebookUrl.isNotEmpty) 'Facebook',
    ];
    return names.join(' · ');
  }

  List<({String label, String url, IconData icon})> get chips => [
        if (youtubeUrl.isNotEmpty) (label: 'YouTube', url: youtubeUrl, icon: Icons.play_circle_outline_rounded),
        if (instagramUrl.isNotEmpty) (label: 'Instagram', url: instagramUrl, icon: Icons.camera_alt_outlined),
        if (facebookUrl.isNotEmpty) (label: 'Facebook', url: facebookUrl, icon: Icons.public_outlined),
      ];
}

/// Public https links only. Instagram also accepts `@handle`.
String? sanitizeChefSocialUrl(String? raw, ChefSocialPlatform platform) {
  var value = (raw ?? '').trim();
  if (value.isEmpty || value.length > 300) return null;

  if (platform == ChefSocialPlatform.instagram) {
    final handle = value.replaceFirst(RegExp(r'^@'), '');
    if (!handle.contains('://') && RegExp(r'^[A-Za-z0-9._]{1,30}$').hasMatch(handle)) {
      value = 'https://www.instagram.com/$handle';
    }
  }

  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.userInfo.isNotEmpty) return null;
  final host = uri.host.toLowerCase();
  final allowed = switch (platform) {
    ChefSocialPlatform.instagram => const {'instagram.com', 'www.instagram.com'},
    ChefSocialPlatform.youtube => const {
        'youtube.com',
        'www.youtube.com',
        'm.youtube.com',
        'youtu.be',
        'www.youtu.be',
      },
    ChefSocialPlatform.facebook => const {
        'facebook.com',
        'www.facebook.com',
        'm.facebook.com',
        'fb.com',
        'www.fb.com',
      },
  };
  if (!allowed.contains(host)) return null;
  if ((host == 'youtu.be' || host == 'www.youtu.be') && uri.pathSegments.isEmpty) return null;
  return uri.replace(scheme: 'https').toString();
}

const kChefCardLocales = ['en', 'hi', 'mr'];

String normalizeChefCardLocale(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (kChefCardLocales.contains(value)) return value;
  return 'en';
}

String chefCardLocaleLabel(String? locale) {
  switch (normalizeChefCardLocale(locale)) {
    case 'hi':
      return 'हिन्दी';
    case 'mr':
      return 'मराठी';
    default:
      return 'English';
  }
}

/// Prefers a local-script kitchen name when the chef set one for their card.
String chefCardDisplayName(
  Map<String, dynamic>? data, {
  String? locale,
  String fallback = 'Home Kitchen',
}) {
  final localName = data?['local_kitchen_name']?.toString().trim() ?? '';
  final cardLocale = normalizeChefCardLocale(locale ?? data?['card_locale']?.toString());
  if (localName.isNotEmpty && cardLocale != 'en') return localName;
  return chefDisplayName(data, fallback: fallback);
}

class ChefCardCopy {
  const ChefCardCopy({
    required this.homeKitchen,
    required this.preparedBy,
    required this.fssaiListed,
    required this.fssaiMissing,
    required this.tapForInfo,
    required this.partnerSince,
    required this.recentReviews,
    required this.newKitchen,
    required this.cookedMeals,
    required this.followKitchen,
    required this.following,
  });

  final String homeKitchen;
  final String preparedBy;
  final String fssaiListed;
  final String fssaiMissing;
  final String tapForInfo;
  final String partnerSince;
  final String recentReviews;
  final String newKitchen;
  final String Function(int count) cookedMeals;
  final String followKitchen;
  final String following;
}

ChefCardCopy chefCardCopy(String? locale) {
  switch (normalizeChefCardLocale(locale)) {
    case 'hi':
      return ChefCardCopy(
        homeKitchen: 'घर का किचन',
        preparedBy: 'तैयार किया',
        fssaiListed: 'FSSAI',
        fssaiMissing: 'FSSAI सूची में नहीं',
        tapForInfo: 'जानकारी के लिए टैप करें',
        partnerSince: 'पार्टनर से',
        recentReviews: 'हाल की समीक्षाएँ',
        newKitchen: 'नया किचन',
        cookedMeals: (count) => count <= 0 ? 'नया किचन' : '$count प्लेटें पकाईं',
        followKitchen: 'किचन फॉलो करें',
        following: 'फॉलो कर रहे हैं',
      );
    case 'mr':
      return ChefCardCopy(
        homeKitchen: 'घरची स्वयंपाकघर',
        preparedBy: 'तयार केले',
        fssaiListed: 'FSSAI',
        fssaiMissing: 'FSSAI नोंद नाही',
        tapForInfo: 'माहितीसाठी टॅप करा',
        partnerSince: 'पार्टनर पासून',
        recentReviews: 'अलीकडील रिव्ह्यू',
        newKitchen: 'नवी स्वयंपाकघर',
        cookedMeals: (count) => count <= 0 ? 'नवी स्वयंपाकघर' : '$count ताट शिजवली',
        followKitchen: 'स्वयंपाकघर फॉलो करा',
        following: 'फॉलो करत आहात',
      );
    default:
      return ChefCardCopy(
        homeKitchen: 'Home kitchen',
        preparedBy: 'Prepared by',
        fssaiListed: 'FSSAI',
        fssaiMissing: 'FSSAI not listed yet',
        tapForInfo: 'Tap for kitchen info',
        partnerSince: 'Partner since',
        recentReviews: 'Recent reviews',
        newKitchen: 'New kitchen',
        cookedMeals: (count) => count <= 0 ? 'New kitchen' : 'Cooked $count meals',
        followKitchen: 'Follow kitchen',
        following: 'Following',
      );
  }
}

class ChefRatingSummary {
  const ChefRatingSummary({this.average = 0, this.count = 0});

  final double average;
  final int count;

  bool get hasReviews => count > 0;

  String get label {
    if (!hasReviews) return 'No ratings yet';
    final reviews = count == 1 ? '1 review' : '$count reviews';
    return '${average.toStringAsFixed(1)} · $reviews';
  }
}

List<String> kitchenPhotosFrom(dynamic raw) {
  Iterable<dynamic> values = const [];
  if (raw is Iterable) {
    values = raw;
  } else if (raw is String && raw.trim().isNotEmpty) {
    if (raw.trim().startsWith('[')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Iterable) values = decoded;
      } catch (_) {
        values = [raw];
      }
    } else {
      values = [raw];
    }
  }
  final photos = <String>[];
  for (final value in values) {
    final url = value.toString().trim();
    if (url.startsWith('http') && !photos.contains(url)) photos.add(url);
    if (photos.length >= 3) break;
  }
  return photos;
}

String kitchenStoryArea({String? city, String? address}) {
  final town = (city ?? '').trim();
  if (town.isNotEmpty) return town;
  final line = (address ?? '').trim();
  if (line.isEmpty) return '';
  final parts = line.split(',').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  if (parts.length >= 2) return parts[parts.length - 2];
  return parts.isEmpty ? '' : parts.first;
}

int cookedMealCountFromOrders(Iterable<dynamic> rows) {
  var count = 0;
  for (final row in rows) {
    if (row is! Map) continue;
    final status = row['status']?.toString().toLowerCase() ?? '';
    if (status.contains('cancel') || status.contains('reject')) continue;
    if (status.contains('out for delivery') || status.contains('out_for_delivery')) {
      count++;
      continue;
    }
    if (status.contains('delivered') ||
        status.contains('completed') ||
        status.contains('ready') ||
        status.contains('assigned')) {
      count++;
    }
  }
  return count;
}

String cookedMealsLabel(int count) {
  if (count <= 0) return 'New kitchen';
  if (count == 1) return 'Cooked 1 meal';
  return 'Cooked $count meals';
}

const int kKitchenLivePhotoHours = 4;

bool isKitchenLivePhotoFresh(DateTime? takenAt, {DateTime? now}) {
  if (takenAt == null) return false;
  final current = (now ?? DateTime.now()).toLocal();
  final taken = takenAt.toLocal();
  final age = current.difference(taken);
  return !age.isNegative && age <= const Duration(hours: kKitchenLivePhotoHours);
}

String kitchenLivePhotoLabel(DateTime? takenAt, {DateTime? now}) {
  if (!isKitchenLivePhotoFresh(takenAt, now: now)) return '';
  final minutes = (now ?? DateTime.now()).toLocal().difference(takenAt!.toLocal()).inMinutes;
  if (minutes < 1) return 'Fresh kitchen photo · just now';
  if (minutes < 60) return 'Fresh kitchen photo · ${minutes}m ago';
  final hours = minutes ~/ 60;
  return 'Fresh kitchen photo · ${hours}h ago';
}

String? orderDispatchPhotoUrl(Map<String, dynamic>? order) {
  if (order == null) return null;
  final url = (order['dispatch_photo_url'] ?? order['dispatchPhotoUrl'])?.toString().trim() ?? '';
  return url.startsWith('http') ? url : null;
}

DateTime? orderDispatchPhotoAt(Map<String, dynamic>? order) {
  if (order == null) return null;
  return DateTime.tryParse(order['dispatch_photo_at']?.toString() ?? '');
}

bool hasDispatchPhoto(Map<String, dynamic>? order) => orderDispatchPhotoUrl(order) != null;

String? orderPodPhotoUrl(Map<String, dynamic>? order) {
  if (order == null) return null;
  final url = (order['pod_photo_url'] ?? order['podPhotoUrl'])?.toString().trim() ?? '';
  return url.startsWith('http') ? url : null;
}

DateTime? orderPodPhotoAt(Map<String, dynamic>? order) {
  if (order == null) return null;
  return DateTime.tryParse(order['pod_captured_at']?.toString() ?? order['pod_photo_at']?.toString() ?? '');
}

bool hasPodPhoto(Map<String, dynamic>? order) => orderPodPhotoUrl(order) != null;

String deliveryPodLabel({DateTime? takenAt, DateTime? now}) {
  final when = takenAt?.toLocal();
  if (when == null) return 'Delivered · door photo on file';
  return 'Delivered · door photo ${formatAppTime(when)}';
}

String dinerDoubleChargeCopy({required bool extraDebitShown}) {
  if (extraDebitShown) {
    return 'If your bank shows two HotPotChef debits, we keep one payment and refund the duplicate in 5–7 business days. Open Support with the Razorpay id if the extra debit stays.';
  }
  return 'Nothing extra was charged. A bank hold can still show for a day and then drop on its own.';
}

String dinerRefundMoneyCopy({required bool refunded}) {
  if (refunded) {
    return 'Refund started. The amount should return to the original method in 5–7 business days.';
  }
  return 'We are issuing a refund to the original method. If it is not visible in 5–7 business days, open Support with the order id.';
}

String dinerPaymentFailureCopy(String? gatewayMessage) {
  final text = (gatewayMessage ?? '').toLowerCase();
  if (text.contains('already') || text.contains('duplicate') || text.contains('paid')) {
    return dinerDoubleChargeCopy(extraDebitShown: true);
  }
  if (text.contains('refund')) {
    return dinerRefundMoneyCopy(refunded: true);
  }
  return 'Payment did not complete. Nothing was confirmed on this order. If a hold appears on your bank statement, it drops in 5–7 business days.';
}

String dispatchPackedLabel({DateTime? takenAt, DateTime? now}) {
  final when = takenAt?.toLocal();
  if (when == null) return 'Your box is packed';
  final minutes = (now ?? DateTime.now()).toLocal().difference(when).inMinutes;
  if (minutes < 1) return 'Your box is packed · just now';
  if (minutes < 60) return 'Your box is packed · ${minutes}m ago';
  return 'Your box is packed';
}

ChefRatingSummary chefRatingSummaryFromRows(Iterable<dynamic> rows) {
  var sum = 0.0;
  var count = 0;
  for (final row in rows) {
    if (row is! Map) continue;
    final rating = double.tryParse(row['rating']?.toString() ?? '');
    if (rating == null) continue;
    sum += rating;
    count++;
  }
  if (count == 0) return const ChefRatingSummary();
  return ChefRatingSummary(average: sum / count, count: count);
}

/// Re-price cart extras from the published meal. Unknown extras are dropped.
List<CartItemAddOn> pricedAddOnsFromCatalog({
  required dynamic catalog,
  required Iterable<CartItemAddOn> selected,
}) {
  if (selected.isEmpty) return const [];
  dynamic decoded = catalog;
  if (decoded is String && decoded.trim().isNotEmpty) {
    try {
      decoded = jsonDecode(decoded);
    } catch (_) {
      decoded = null;
    }
  }
  if (decoded is List && decoded.isEmpty) return const [];
  final priced = PricingCalculator.catalogPricedAddOns(
    catalog: catalog,
    selected: [for (final addon in selected) addon.toJson()],
  );
  if (decoded is List && decoded.isNotEmpty) {
    return priced
        .map((row) => CartItemAddOn(
              id: row['id']?.toString() ?? '',
              title: row['title']?.toString() ?? 'Add-on',
              price: (row['price'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
  }
  return selected.toList();
}

const String kFeedSortNearby = 'Nearby';
const String kFeedSortPrice = 'Price';
const String kFeedSortRating = 'Rating';
const String kFeedSortEta = 'Arriving soon';

List<Map<String, dynamic>> sortFeedMeals(
  List<Map<String, dynamic>> meals, {
  required String sort,
  required double? Function(Map<String, dynamic> meal) distanceKm,
  double Function(Map<String, dynamic> meal)? rating,
  int Function(Map<String, dynamic> meal)? etaMinutes,
}) {
  final copy = List<Map<String, dynamic>>.from(meals);
  int byDistance(Map<String, dynamic> a, Map<String, dynamic> b) {
    final da = distanceKm(a);
    final db = distanceKm(b);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  copy.sort((a, b) {
    switch (sort) {
      case kFeedSortPrice:
        final pa = PricingCalculator.effectiveUnitPrice(a, 1);
        final pb = PricingCalculator.effectiveUnitPrice(b, 1);
        final compared = pa.compareTo(pb);
        return compared != 0 ? compared : byDistance(a, b);
      case kFeedSortRating:
        final ra = rating?.call(a) ?? 0;
        final rb = rating?.call(b) ?? 0;
        final compared = rb.compareTo(ra);
        return compared != 0 ? compared : byDistance(a, b);
      case kFeedSortEta:
        final ea = etaMinutes?.call(a) ?? 9999;
        final eb = etaMinutes?.call(b) ?? 9999;
        final compared = ea.compareTo(eb);
        return compared != 0 ? compared : byDistance(a, b);
      case kFeedSortNearby:
      default:
        return byDistance(a, b);
    }
  });
  return copy;
}

int compareKitchenOrdersBySlot(Map<String, dynamic> a, Map<String, dynamic> b, {DateTime? now}) {
  final startA = orderSlotStart(a, now: now);
  final startB = orderSlotStart(b, now: now);
  if (startA == null && startB == null) {
    return (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString());
  }
  if (startA == null) return 1;
  if (startB == null) return -1;
  final slot = startA.compareTo(startB);
  if (slot != 0) return slot;
  return (a['created_at'] ?? '').toString().compareTo((b['created_at'] ?? '').toString());
}

double lineItemUnitPrice(Map<String, dynamic> item) {
  final meal = PricingCalculator.pricingSourceFromLine(item);
  final addonsUnit = parseMoney(item['addons_unit']);
  final legacyAddons = addonsUnit > 0
      ? 0.0
      : PricingCalculator.addOnsTotal(item['selectedAddOns'] ?? item['selected_add_ons']);
  final unit = parseMoney(
    item['base_price'] ?? item['basePrice'] ?? item['price'] ?? item['unit_price'] ?? meal['price'],
  );
  final ceiling = unit + (addonsUnit > 0 ? addonsUnit : 0);
  final discounted = parseMoney(item['discounted_price'] ?? item['discountedPrice']);
  if (discounted > 0 && (ceiling <= 0 || discounted <= ceiling + 0.001)) {
    return discounted;
  }
  final storedNet = parseMoney(item['line_net']);
  final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
  if (storedNet > 0 && qty > 0) {
    return PricingCalculator.roundCurrency(storedNet / qty);
  }
  final appliedPromo = item['applied_promo_code']?.toString();
  if (PricingCalculator.isOfferActive(meal, appliedPromoCode: appliedPromo) ||
      PricingCalculator.promoCodeMatches(meal, appliedPromo)) {
    return PricingCalculator.effectiveUnitPrice(meal, qty, appliedPromoCode: appliedPromo) +
        (addonsUnit > 0 ? addonsUnit : legacyAddons);
  }
  return unit + (addonsUnit > 0 ? addonsUnit : legacyAddons);
}

/// Pre-discount list price for a cart/order line (base + add-ons).
double lineItemListPrice(Map<String, dynamic> item) {
  final meal = PricingCalculator.pricingSourceFromLine(item);
  final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
  final storedGross = parseMoney(item['line_gross']);
  if (storedGross > 0 && qty > 0) {
    return PricingCalculator.roundCurrency(storedGross / qty);
  }

  final addonsUnit = parseMoney(item['addons_unit']);
  final legacyAddons = addonsUnit > 0
      ? 0.0
      : PricingCalculator.addOnsTotal(item['selectedAddOns'] ?? item['selected_add_ons']);
  final extras = addonsUnit > 0 ? addonsUnit : legacyAddons;
  final base = parseMoney(
    item['base_price'] ?? item['basePrice'] ?? meal['price'] ?? item['unit_price'] ?? item['price'],
  );
  if (base > 0) return PricingCalculator.roundCurrency(base + extras);
  return lineItemUnitPrice(item);
}

String? orderPromoLabel({
  required List<Map<String, dynamic>> items,
  Map<String, dynamic>? order,
}) {
  final source = order ?? (items.isNotEmpty ? items.first : const <String, dynamic>{});
  final fromOrder = PricingCalculator.normalizedPromoCode(
    source['applied_promo_code'] ?? source['appliedPromoCode'] ?? source['promo_code'],
  );
  if (fromOrder != null) return fromOrder;

  for (final item in items) {
    final applied = PricingCalculator.normalizedPromoCode(
      item['applied_promo_code'] ?? item['appliedPromoCode'],
    );
    if (applied != null) return applied;
  }
  for (final item in items) {
    final code = PricingCalculator.mealPromoCode(PricingCalculator.pricingSourceFromLine(item));
    if (code != null) return code;
  }
  for (final item in items) {
    final description = item['offer_description']?.toString().trim() ?? '';
    if (description.isNotEmpty) return description;
  }
  return 'Offer';
}

class ChefPayoutBreakdown {
  const ChefPayoutBreakdown({
    required this.foodAndPackaging,
    required this.marginRate,
    required this.margin,
    required this.chefPayout,
  });

  final double foodAndPackaging;
  final double marginRate;
  final double margin;
  final double chefPayout;
}

double estimatedPlatformMargin({
  required double gmv,
  required double deliveryFeeSum,
  double tipSum = 0,
  double marginRate = kPlatformMarginRate,
}) {
  final base = (gmv - deliveryFeeSum - tipSum).clamp(0, double.infinity).toDouble();
  return roundMoney(base * marginRate);
}

/// Chef earns food + packaging after platform margin. Delivery fee is not included.
ChefPayoutBreakdown chefPayoutBreakdown({
  required double itemsTotal,
  required double packagingFee,
  double marginRate = kPlatformMarginRate,
}) {
  final base = roundMoney((itemsTotal + packagingFee).clamp(0, double.infinity).toDouble());
  final payout = roundMoney(base * (1 - marginRate));
  return ChefPayoutBreakdown(
    foodAndPackaging: base,
    marginRate: marginRate,
    margin: roundMoney(base - payout),
    chefPayout: payout,
  );
}

/// Kitchen take-home: stored `chef_payout` when released, else 85% of food+pack (not diner GMV).
ChefPayoutBreakdown chefPayoutForOrder(Map<String, dynamic> order) {
  final items = parseOrderItemsList(order['items'] ?? order['cart_items']);
  final bill = orderBillBreakdown(items: items, order: order);
  final computed = chefPayoutBreakdown(itemsTotal: bill.itemsTotal, packagingFee: bill.packagingFee);
  final settled = parseMoney(order['chef_payout']);
  if (settled > 0) {
    return ChefPayoutBreakdown(
      foodAndPackaging: computed.foodAndPackaging,
      marginRate: computed.marginRate,
      margin: roundMoney((computed.foodAndPackaging - settled).clamp(0, double.infinity).toDouble()),
      chefPayout: settled,
    );
  }
  return computed;
}

bool isPartnerDeliveryOrder(Map<String, dynamic> order) {
  final raw = (order['order_type'] ?? order['service_type'] ?? '').toString().trim();
  if (raw.isNotEmpty) {
    return ServiceType.fromString(raw).usesDeliveryPartner;
  }
  final items = parseOrderItemsList(order['items'] ?? order['cart_items']);
  for (final item in items) {
    final token = (item['selected_service_type'] ?? item['service_type'] ?? item['serviceType'] ?? '')
        .toString()
        .trim();
    if (token.isEmpty) continue;
    if (!ServiceType.fromString(token).usesDeliveryPartner) return false;
  }
  return true;
}


class OrderBillBreakdown {
  const OrderBillBreakdown({
    required this.itemsTotal,
    required this.packagingFee,
    required this.deliveryFee,
    required this.tipAmount,
    required this.coinsApplied,
    required this.grandTotal,
    this.itemsGross = 0,
    this.promoDiscount = 0,
    this.promoLabel,
    this.membershipFee = 0,
  });

  /// Food portion actually charged (after offer).
  final double itemsTotal;
  final double packagingFee;
  final double deliveryFee;
  final double tipAmount;
  final double coinsApplied;
  final double grandTotal;

  /// Pre-discount food total for the bill display.
  final double itemsGross;
  final double promoDiscount;
  final String? promoLabel;
  final double membershipFee;

  double get displayItemsTotal =>
      itemsGross > itemsTotal + 0.5 ? itemsGross : (itemsGross > 0 ? itemsGross : itemsTotal);
}

/// Builds the bill from the stored paid total when present, instead of a hardcoded delivery fee.
OrderBillBreakdown orderBillBreakdown({
  required List<Map<String, dynamic>> items,
  Map<String, dynamic>? order,
  bool hasDelivery = false,
}) {
  final source = order ?? (items.isNotEmpty ? items.first : const <String, dynamic>{});

  var itemsTotal = 0.0;
  var itemsGross = 0.0;
  for (final item in items) {
    final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
    itemsTotal += lineItemUnitPrice(item) * qty;
    itemsGross += lineItemListPrice(item) * qty;
  }
  if (itemsGross + 0.5 < itemsTotal) itemsGross = itemsTotal;
  final promoDiscount = PricingCalculator.roundCurrency(
    itemsGross > itemsTotal ? itemsGross - itemsTotal : 0,
  );
  final promoLabel = promoDiscount > 0.5
      ? orderPromoLabel(items: items, order: source)
      : null;

  final paidTotal = parseMoney(source['total_price'] ?? source['total_amount'] ?? source['grand_total']);
  final storedPackaging = tryParseMoney(source['packaging_fee']);
  var packaging = storedPackaging ?? 0;
  final tip = parseMoney(source['tip_amount'] ?? source['tip']);
  var coins = parseMoney(source['coins_applied']);
  final storedDelivery = tryParseMoney(source['delivery_fee']);
  final membershipFee = parseMoney(source['membership_fee']);

  final service = (source['order_type'] ?? source['service_type'] ?? '').toString().toLowerCase();
  final deliveryExpected = hasDelivery || service.contains('delivery');

  double delivery;
  if (!deliveryExpected) {
    delivery = storedDelivery ?? 0;
  } else if (storedDelivery != null) {
    delivery = storedDelivery;
  } else if (paidTotal > 0) {
    delivery = paidTotal - itemsTotal - packaging - tip + coins - membershipFee;
    if (delivery < 0) delivery = 0;
  } else {
    delivery = 0;
  }

  if (storedPackaging == null && paidTotal > 0) {
    final remainder = paidTotal - itemsTotal - delivery - tip + coins - membershipFee;
    if (remainder > 0.5) packaging = remainder;
  }

  final extras = packaging + delivery + tip + membershipFee;
  // Older rows stored food-only in total_price (e.g. ₹221) while packaging still applies.
  final paidLooksLikeItemsOnly =
      paidTotal > 0 && (paidTotal - itemsTotal).abs() < 0.5 && extras >= 0.5;

  final computed = (itemsTotal + packaging + delivery + tip + membershipFee - coins).clamp(0, double.infinity);
  final grand = (paidTotal > 0 && !paidLooksLikeItemsOnly) ? paidTotal : computed;

  var shownPromo = promoDiscount;
  var shownLabel = promoLabel;
  final feesAreStored = storedPackaging != null && (storedDelivery != null || !deliveryExpected);
  final linesCarryOffer = items.any((item) {
    final type = (item['offer_type'] ?? '').toString().toLowerCase();
    return type.contains('percent') ||
        type.contains('flat') ||
        type.contains('flash') ||
        type.contains('bogo') ||
        type.contains('buy');
  });
  if (feesAreStored && shownPromo <= 0.5 && linesCarryOffer) {
    final unexplained = PricingCalculator.roundCurrency((computed - grand).toDouble());
    if (unexplained > 0.5) {
      shownPromo = unexplained.roundToDouble();
      shownLabel ??= 'Offer';
    }
  }

  return OrderBillBreakdown(
    itemsTotal: itemsTotal,
    packagingFee: packaging,
    deliveryFee: delivery,
    tipAmount: tip,
    coinsApplied: coins,
    grandTotal: grand.toDouble(),
    itemsGross: itemsGross,
    promoDiscount: shownPromo,
    promoLabel: shownLabel,
    membershipFee: membershipFee,
  );
}

List<Widget> orderBillItemRows(BuildContext context, OrderBillBreakdown bill) {
  final ink = AppTheme.onSurfaceOf(context);
  return [
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Item total', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        Text(
          '₹${bill.displayItemsTotal.toInt()}',
          style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    ),
    if (bill.promoDiscount > 0.5) ...[
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Promo (${bill.promoLabel ?? 'Offer'})',
            style: const TextStyle(color: AppTheme.success, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Text(
            '-₹${bill.promoDiscount.toInt()}',
            style: const TextStyle(color: AppTheme.success, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ],
  ];
}

List<Widget> orderBillAdjustmentRows(BuildContext context, OrderBillBreakdown bill) {
  final ink = AppTheme.onSurfaceOf(context);
  final rows = <Widget>[];
  if (bill.membershipFee > 0) {
    rows.addAll([
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Family member', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          Text('₹${bill.membershipFee.toInt()}', style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
      Text(membershipGstLineLabel(bill.membershipFee), style: AppTheme.micro),
    ]);
  }
  if (bill.tipAmount > 0) {
    rows.addAll([
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Tip', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          Text('₹${bill.tipAmount.toInt()}', style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    ]);
  }
  if (bill.coinsApplied > 0) {
    rows.addAll([
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('HotPot Coins', style: TextStyle(color: AppTheme.success, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(
            '-₹${bill.coinsApplied.toInt()}',
            style: const TextStyle(color: AppTheme.success, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ]);
  }
  return rows;
}

String friendlyAuthError(Object error) {
  if (error is NetworkException) return error.message;
  final network = networkErrorMessage(error);
  if (network == NetworkException.timedOutMessage || network == NetworkException.offlineMessage) {
    return network;
  }

  final text = error.toString().toLowerCase();
  if (text.contains('invalid login') ||
      text.contains('invalid credentials') ||
      text.contains('invalid email or password') ||
      text.contains('wrong email or password')) {
    return 'Wrong email or password. Please try again.';
  }
  if (text.contains('email not confirmed')) {
    return 'Please confirm your email before signing in.';
  }
  if (text.contains('already registered') || text.contains('already been registered')) {
    return 'An account with this email already exists. Try signing in.';
  }
  if (text.contains('network') || text.contains('failed host lookup')) {
    return 'Network issue. Check your connection and try again.';
  }
  return 'Sign-in failed. Please check your details and try again.';
}


bool driverRunIsOutForDelivery(String? status) {
  final s = (status ?? '').toLowerCase();
  return s.contains('out');
}

String formatMapCoordinateLabel(double? lat, double? lng) {
  if (lat == null || lng == null) return '';
  if (lat == 0 && lng == 0) return '';
  return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
}

Uri? googleMapsDirectionsUri({
  double? lat,
  double? lng,
  String? address,
  bool preferAddress = false,
}) {
  final text = (address ?? '').trim();
  if (preferAddress && text.isNotEmpty) {
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(text)}&travelmode=driving',
    );
  }
  if (lat != null && lng != null && lat != 0 && lng != 0) {
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
  }
  if (text.isEmpty) return null;
  return Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(text)}&travelmode=driving',
  );
}


const double kCateringLeadRadiusKm = 25;

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthKm = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
  return earthKm * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double? cateringLeadDistanceKm(
  Map<String, dynamic> request, [
  Map<String, dynamic>? chefPin,
]) {
  final lat = addressCoordinate(request, latitude: true);
  final lng = addressCoordinate(request, latitude: false);
  final chefLat = kitchenCoordinate(chefPin, latitude: true) ??
      addressCoordinate(chefPin, latitude: true);
  final chefLng = kitchenCoordinate(chefPin, latitude: false) ??
      addressCoordinate(chefPin, latitude: false);
  if (lat == null || lng == null || chefLat == null || chefLng == null) return null;
  return haversineKm(chefLat, chefLng, lat, lng);
}

bool isCateringLeadInRange(
  Map<String, dynamic> request, [
  Map<String, dynamic>? chefPin,
  double radiusKm = kCateringLeadRadiusKm,
]) {
  final distance = cateringLeadDistanceKm(request, chefPin);
  if (distance == null) return true;
  return distance <= radiusKm;
}

/// Empty list means the diner broadcast to all nearby kitchens.
List<String> cateringLeadTargetChefIds(Map<String, dynamic>? request) {
  final raw = request?['target_chef_ids'];
  if (raw == null) return const [];
  if (raw is List) {
    return raw
        .map((id) => id.toString().trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

bool isCateringLeadTargeted(Map<String, dynamic>? request) =>
    cateringLeadTargetChefIds(request).isNotEmpty;

/// Targeted invites skip the 25 km radius so a chosen kitchen always sees the lead.
bool isCateringLeadVisibleToChef(
  Map<String, dynamic> request, {
  required String chefId,
  Map<String, dynamic>? chefPin,
  double radiusKm = kCateringLeadRadiusKm,
}) {
  if (chefId.trim().isEmpty) return false;
  final targets = cateringLeadTargetChefIds(request);
  if (targets.isNotEmpty) return targets.contains(chefId);
  return isCateringLeadInRange(request, chefPin, radiusKm);
}

bool canPaySharedCart({
  String? roomCode,
  String? hostId,
  String? userId,
}) {
  if (roomCode == null || roomCode.trim().isEmpty) return true;
  if (userId == null || userId.isEmpty) return false;
  if (hostId == null || hostId.isEmpty) return true;
  return hostId == userId;
}

String? favoriteCategoryFromPastItems(Iterable<Map<String, dynamic>> items) {
  final counts = <String, int>{};
  for (final item in items) {
    final category = item['category']?.toString().trim() ?? '';
    if (category.isEmpty) continue;
    counts[category] = (counts[category] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

List<Map<String, dynamic>> parseOrderItemsList(dynamic raw) {
  dynamic parsed = raw;
  for (var i = 0; i < 2; i++) {
    if (parsed is String && parsed.trim().isNotEmpty) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        return const [];
      }
    }
  }
  if (parsed is Map) return [Map<String, dynamic>.from(parsed)];
  if (parsed is! List) return const [];
  return parsed.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
}

bool isChefKitchenOpen(Map<String, dynamic>? profile) {
  if (profile == null) return true;
  if (!profile.containsKey('is_open') && !profile.containsKey('isOpen')) return true;
  final raw = profile['is_open'] ?? profile['isOpen'];
  if (raw == null) return true;
  if (raw is bool) return raw;
  final text = raw.toString().toLowerCase().trim();
  if (text == 'false' || text == '0' || text == 'offline' || text == 'closed') return false;
  return true;
}

bool isChefKitchenAcceptingOrders(Map<String, dynamic>? profile, {DateTime? now}) {
  return isChefKitchenOpen(profile);
}

Map<String, double> kitchenPinMealFields(double lat, double lng) {
  return {
    'pickup_lat': lat,
    'pickup_lng': lng,
  };
}

Map<String, dynamic> mealWithKitchenPin(
  Map<String, dynamic> meal, {
  Map<String, dynamic>? chefPin,
}) {
  if (hasKitchenPin(meal) || chefPin == null) return meal;
  final lat = kitchenCoordinate(chefPin, latitude: true);
  final lng = kitchenCoordinate(chefPin, latitude: false);
  if (lat == null || lng == null) return meal;
  return {
    ...meal,
    'pickup_lat': lat,
    'pickup_lng': lng,
    'chef_lat': lat,
    'chef_lng': lng,
  };
}

/// Matches Home meal-grid radius: road-adjusted haversine ≤ [maxRoadKm].
/// No destination and no kitchen pin both hide the meal (do not guess a city).
bool mealInDeliveryRadius(
  Map<String, dynamic> meal, {
  double? destinationLat,
  double? destinationLng,
  double maxRoadKm = 15,
  double roadMultiplier = 1.3,
}) {
  if (destinationLat == null || destinationLng == null) return false;
  if (destinationLat == 0 || destinationLng == 0) return false;
  return kitchenServesDinerPin(
    kitchenLat: kitchenCoordinate(meal, latitude: true),
    kitchenLng: kitchenCoordinate(meal, latitude: false),
    dinerLat: destinationLat,
    dinerLng: destinationLng,
  );
}


/// Builds a checkout payload from a selected catering / bulk request.
List<Map<String, dynamic>> checkoutItemsFromCateringRequest(Map<String, dynamic> request) {
  final quantity = int.tryParse(request['quantity']?.toString() ?? '1') ?? 1;
  final budget = cateringPayableTotal(request);
  final unitPrice = quantity > 0 ? roundMoney(budget / quantity) : budget;
  final chefId = request['accepted_chef_id']?.toString() ?? '';
  final title = request['title']?.toString() ?? 'Catering order';
  final service = request['service_type']?.toString() ?? 'Delivery Partner';
  final target = DateTime.tryParse(request['target_date_time']?.toString() ?? '');
  final scheduled = target?.toLocal() ?? DateTime.now().add(const Duration(days: 1));
  final timeSlot =
      '${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}';

  return [
    {
      'chef_id': chefId,
      'chefId': chefId,
      'chef_name': request['accepted_chef_name'],
      'title': title,
      'name': title,
      'quantity': quantity < 1 ? 1 : quantity,
      'price': unitPrice,
      'base_price': unitPrice,
      'selected_service_type': service,
      'service_type': service,
      'serviceType': service,
      'scheduled_date': scheduled.toIso8601String(),
      'scheduledDate': scheduled.toIso8601String(),
      'selected_date': scheduled.toIso8601String(),
      'time_slot': timeSlot,
      'timeSlot': timeSlot,
      'source_request_id': request['id'],
      'specialInstructions': request['description'],
    },
  ];
}

List<Map<String, dynamic>> orderItemsFrom(dynamic rawItems) {
  if (rawItems is List) {
    return rawItems
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (rawItems is String && rawItems.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(rawItems);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
  }
  return const [];
}

String walletOrderDishLine(dynamic items) {
  final parsed = orderItemsFrom(items);
  if (parsed.isEmpty) {
    final fallback = mealTitleFromItems(items);
    return fallback == 'your order' ? 'Order' : fallback;
  }
  final first = parsed.first;
  final title = (first['title'] ?? first['name'] ?? first['meal_name'] ?? 'Meal')
      .toString()
      .trim();
  final label = title.isEmpty ? 'Meal' : title;
  if (parsed.length > 1) return '$label (+${parsed.length - 1} more)';
  return label;
}

String walletOrderStatusLabel(String? status) {
  final raw = (status ?? '').trim().replaceAll('_', ' ');
  if (raw.isEmpty) return 'Placed';
  return raw
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

class WalletOrderSummary {
  const WalletOrderSummary({
    required this.orderRef,
    required this.dishLine,
    required this.statusLabel,
    required this.total,
    required this.coinsApplied,
    this.at,
  });

  final String orderRef;
  final String dishLine;
  final String statusLabel;
  final double total;
  final double coinsApplied;
  final DateTime? at;
}

WalletOrderSummary walletOrderSummaryFrom(Map<String, dynamic> order) {
  final coins = (order['coins_applied'] as num?)?.toDouble() ??
      double.tryParse(order['coins_applied']?.toString() ?? '') ??
      0.0;
  final total = (order['total_price'] as num?)?.toDouble() ??
      (order['total_amount'] as num?)?.toDouble() ??
      (order['price'] as num?)?.toDouble() ??
      0.0;
  return WalletOrderSummary(
    orderRef: formatOrderId(order['order_id']?.toString(), order['id']?.toString() ?? ''),
    dishLine: walletOrderDishLine(order['items'] ?? order['cart_items']),
    statusLabel: walletOrderStatusLabel(order['status']?.toString()),
    total: total,
    coinsApplied: coins,
    at: DateTime.tryParse(order['created_at']?.toString() ?? ''),
  );
}

List<WalletOrderSummary> walletOrderSummaries(
  List<Map<String, dynamic>> orders, {
  int limit = 12,
}) {
  return orders.take(limit).map(walletOrderSummaryFrom).toList();
}

class CoinLedgerEntry {
  const CoinLedgerEntry({
    required this.title,
    required this.amount,
    this.at,
    required this.isDebit,
    this.orderRef,
    this.detail,
  });

  final String title;
  final double amount;
  final DateTime? at;
  final bool isDebit;
  /// Brief order id when this debit is tied to a kitchen order.
  final String? orderRef;
  /// Dish and rupee line when a checkout debit is matched to an order.
  final String? detail;
}

bool isCoinLedgerDebit(String? type, double amount) {
  if (amount < 0) return true;
  return RegExp('debit|spent|redeem|used|deduct|payment|payout', caseSensitive: false)
      .hasMatch(type ?? '');
}

/// Groups wallet copy that is logged twice (trigger + explicit insert).
String coinActivityFamily(String title) {
  final text = title.toLowerCase();
  if (text.contains('streak')) return 'streak';
  if (text.contains('restored') || text.contains('cancel')) return 'restore';
  if (text.contains('referral')) return 'referral';
  if (text.contains('checkout') || text.contains('applied')) return 'checkout';
  if (text.contains('credited') || text.contains('credit')) return 'credit';
  return text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

DateTime? coinActivityMinute(DateTime? at) {
  if (at == null) return null;
  final utc = at.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
}

String coinActivityDedupeKey(Map<String, dynamic> txn) {
  final rawAmount = (txn['amount'] as num?)?.toDouble() ??
      double.tryParse(txn['amount']?.toString() ?? '') ??
      0.0;
  final type = txn['transaction_type']?.toString() ?? '';
  final title = (txn['description']?.toString() ?? type).trim();
  final debit = isCoinLedgerDebit(type, rawAmount);
  final at = coinActivityMinute(DateTime.tryParse(txn['created_at']?.toString() ?? ''));
  return '${coinActivityFamily(title)}|$debit|${rawAmount.abs().toStringAsFixed(2)}|${at?.toIso8601String() ?? ''}';
}

bool _coinTxnHasOrderLink(Map<String, dynamic> txn) {
  final orderId = txn['order_id']?.toString().trim() ?? '';
  return orderId.isNotEmpty;
}

/// Prefer the row that already names an order, else the first seen.
List<Map<String, dynamic>> dedupeCoinTransactions(List<Map<String, dynamic>> transactions) {
  final buckets = <String, Map<String, dynamic>>{};
  final order = <String>[];
  for (final txn in transactions) {
    final key = coinActivityDedupeKey(txn);
    final existing = buckets[key];
    if (existing == null) {
      buckets[key] = txn;
      order.add(key);
      continue;
    }
    if (_coinTxnHasOrderLink(txn) && !_coinTxnHasOrderLink(existing)) {
      buckets[key] = txn;
    }
  }
  return [for (final key in order) buckets[key]!];
}

bool _looksLikeStandaloneCoinCredit(String title, String type) {
  return RegExp(r'streak|referral|signup|welcome', caseSensitive: false)
      .hasMatch('$title $type');
}

/// Checkout spends and order-linked credits (not streak/referral) should show Order #.
bool shouldAttachOrderToCoinRow({
  required String title,
  required String type,
  required bool isDebit,
}) {
  if (_looksLikeStandaloneCoinCredit(title, type)) return false;
  if (isDebit) return true;
  return RegExp(r'credit|cashback|refund|order', caseSensitive: false)
      .hasMatch('$title $type');
}

String coinWalletOrderNumber(String? orderRef) {
  final ref = (orderRef ?? '').trim();
  if (ref.isEmpty) return '';
  final compact = ref.replaceFirst(RegExp(r'^order\s*#?\s*', caseSensitive: false), '');
  if (compact.isEmpty) return '';
  return 'Order #$compact';
}

String coinWalletOrderLine({required bool isDebit, String? orderRef}) {
  final number = coinWalletOrderNumber(orderRef);
  if (number.isEmpty) return '';
  if (isDebit) return 'Used on $number';
  return 'Tied to $number';
}

String? _briefOrderRef(Map<String, dynamic> order) {
  final label = formatOrderId(order['order_id']?.toString(), order['id']?.toString() ?? '');
  if (label.isEmpty) return null;
  return label;
}

Map<String, dynamic>? matchOrderForCoinDebit({
  required double amount,
  required DateTime? at,
  required List<Map<String, dynamic>> orders,
  Set<String>? usedOrderIds,
  bool consume = true,
  Duration window = const Duration(hours: 24),
}) {
  if (orders.isEmpty) return null;
  final used = usedOrderIds ?? <String>{};
  Map<String, dynamic>? best;
  var bestDelta = const Duration(days: 3650);

  bool skipUsed(String id) => consume && id.isNotEmpty && used.contains(id);

  if (amount > 0) {
    for (final order in orders) {
      final id = order['id']?.toString() ?? '';
      if (skipUsed(id)) continue;
      final coins = (order['coins_applied'] as num?)?.toDouble() ??
          double.tryParse(order['coins_applied']?.toString() ?? '') ??
          0.0;
      if ((coins - amount).abs() > 0.01) continue;
      final orderAt = DateTime.tryParse(order['created_at']?.toString() ?? '');
      if (at == null || orderAt == null) {
        best ??= order;
        continue;
      }
      final delta = at.difference(orderAt).abs();
      if (delta > window) continue;
      if (delta <= bestDelta) {
        bestDelta = delta;
        best = order;
      }
    }
  }

  if (best == null && at != null) {
    bestDelta = const Duration(days: 3650);
    for (final order in orders) {
      final id = order['id']?.toString() ?? '';
      if (skipUsed(id)) continue;
      final orderAt = DateTime.tryParse(order['created_at']?.toString() ?? '');
      if (orderAt == null) continue;
      final delta = at.difference(orderAt).abs();
      if (delta > window) continue;
      if (delta <= bestDelta) {
        bestDelta = delta;
        best = order;
      }
    }
  }

  if (best == null) return null;
  final id = best['id']?.toString() ?? '';
  if (consume && id.isNotEmpty) used.add(id);
  return best;
}

/// Matches a coin debit to an order by coins amount and nearby created_at.
String? matchOrderRefForCoinDebit({
  required double amount,
  required DateTime? at,
  required List<Map<String, dynamic>> orders,
  Set<String>? usedOrderIds,
}) {
  final matched = matchOrderForCoinDebit(
    amount: amount,
    at: at,
    orders: orders,
    usedOrderIds: usedOrderIds,
  );
  return matched == null ? null : _briefOrderRef(matched);
}

String? _coinDebitOrderDetail(Map<String, dynamic> order) {
  final summary = walletOrderSummaryFrom(order);
  final bits = <String>[summary.dishLine];
  if (summary.total > 0) bits.add('₹${summary.total.toStringAsFixed(0)}');
  return bits.join(' · ');
}

String coinCheckoutDebitTitle({required String base, String? orderRef}) {
  final cleaned = base.trim().isEmpty ? 'Coins applied at checkout' : base.trim();
  final ref = (orderRef ?? '').trim();
  if (ref.isEmpty) return cleaned;
  if (cleaned.toUpperCase().contains(ref.toUpperCase())) return cleaned;
  return '$cleaned · $ref';
}

List<CoinLedgerEntry> mergeCoinLedger({
  required List<Map<String, dynamic>> transactions,
  required List<Map<String, dynamic>> orders,
}) {
  final entries = <CoinLedgerEntry>[];
  final usedOrderIds = <String>{};
  final uniqueTxns = dedupeCoinTransactions(transactions);

  for (final txn in uniqueTxns) {
    final rawAmount = (txn['amount'] as num?)?.toDouble() ??
        double.tryParse(txn['amount']?.toString() ?? '') ??
        0.0;
    if (rawAmount == 0) continue;
    final type = txn['transaction_type']?.toString() ?? '';
    final debit = isCoinLedgerDebit(type, rawAmount);
    var title = (txn['description']?.toString().trim().isNotEmpty ?? false)
        ? txn['description'].toString()
        : (type.isNotEmpty ? type : 'Coin transaction');
    String? orderRef = txn['order_id']?.toString().trim();
    if (orderRef != null && orderRef.isEmpty) orderRef = null;
    Map<String, dynamic>? matchedOrder;
    if (orderRef != null) {
      final rawOrderId = orderRef;
      for (final o in orders) {
        final id = o['id']?.toString() ?? '';
        final publicId = o['order_id']?.toString() ?? '';
        if (id == rawOrderId || publicId == rawOrderId) {
          matchedOrder = o;
          break;
        }
      }
      orderRef = matchedOrder == null
          ? formatOrderId(rawOrderId, rawOrderId)
          : _briefOrderRef(matchedOrder);
    } else if (shouldAttachOrderToCoinRow(title: title, type: type, isDebit: debit)) {
      matchedOrder = matchOrderForCoinDebit(
        amount: rawAmount.abs(),
        at: DateTime.tryParse(txn['created_at']?.toString() ?? ''),
        orders: orders,
        usedOrderIds: usedOrderIds,
        consume: debit,
      );
      orderRef = matchedOrder == null ? null : _briefOrderRef(matchedOrder);
    }
    entries.add(CoinLedgerEntry(
      title: title,
      amount: rawAmount.abs(),
      at: DateTime.tryParse(txn['created_at']?.toString() ?? ''),
      isDebit: debit,
      orderRef: orderRef,
      detail: matchedOrder == null ? null : _coinDebitOrderDetail(matchedOrder),
    ));
  }

  if (entries.isNotEmpty) {
    entries.sort((a, b) => (b.at ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(a.at ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return entries;
  }

  for (final order in orders) {
    final coins = (order['coins_applied'] as num?)?.toDouble() ??
        double.tryParse(order['coins_applied']?.toString() ?? '') ??
        0.0;
    if (coins <= 0) continue;
    final label = _briefOrderRef(order);
    entries.add(CoinLedgerEntry(
      title: 'Coins applied at checkout',
      amount: coins,
      at: DateTime.tryParse(order['created_at']?.toString() ?? ''),
      isDebit: true,
      orderRef: label,
      detail: _coinDebitOrderDetail(order),
    ));
  }

  entries.sort((a, b) => (b.at ?? DateTime.fromMillisecondsSinceEpoch(0))
      .compareTo(a.at ?? DateTime.fromMillisecondsSinceEpoch(0)));
  return entries;
}
