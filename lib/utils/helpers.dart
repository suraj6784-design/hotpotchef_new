// lib/utils/helpers.dart

import 'dart:convert';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'network.dart';
import 'notification_copy.dart';
import 'pricing_calculator.dart';
import 'meal_nutrition.dart';
import '../models/app_role.dart';
import '../models/pricing_models.dart';

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
}) {
  return chefFssaiPublishBlockReason(
        fssaiNumber: fssaiNumber,
        proofUrl: proofUrl,
        verificationStatus: verificationStatus,
      ) ==
      null;
}

/// Null when the chef may publish. Otherwise a chef-facing reason.
String? chefFssaiPublishBlockReason({
  String? fssaiNumber,
  String? proofUrl,
  String? verificationStatus,
}) {
  if (normalizeFssaiNumber(fssaiNumber) == null) {
    return 'Add a valid 14-digit FSSAI licence number in Chef Profile, then try again.';
  }
  if ((proofUrl ?? '').trim().isEmpty) {
    return 'Upload your FSSAI licence proof in Chef Profile. Publishing requires ops verification.';
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
}) {
  final number = (fssaiNumber ?? '').trim();
  final status = normalizeFssaiVerificationStatus(verificationStatus);
  if (number.isEmpty) return 'FSSAI not listed';
  switch (status) {
    case 'verified':
      return 'FSSAI verified · $number';
    case 'pending':
      return 'FSSAI proof under review · $number';
    case 'rejected':
      return 'FSSAI not verified · $number';
    default:
      return 'FSSAI listed · $number';
  }
}

bool dinerFssaiIsVerified(String? verificationStatus) =>
    normalizeFssaiVerificationStatus(verificationStatus) == 'verified';

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
  return [
    headline,
    'Join my HotPotChef group cart: $code',
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
    default:
      return 0;
  }
}

int chefHubTabIndex(String? tab) {
  switch (tab?.trim().toLowerCase()) {
    case 'dispatch':
      return 1;
    case 'menu':
      return 2;
    case 'history':
      return 3;
    case 'leads':
      return 4;
    case 'supplies':
      return 5;
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
  final current = (status ?? '').trim().toLowerCase();
  if (current.contains('cancel') ||
      current.contains('reject') ||
      current.contains('delivered') ||
      current.contains('complet')) {
    return false;
  }
  return current.contains('ready') || current.contains('assigned') || current.contains('out');
}

String mealDietHaystack(Map<String, dynamic> meal) {
  final tags = meal['health_tags'] ?? meal['tags'] ?? meal['ingredients'];
  final tagText = tags is List ? tags.join(' ') : tags?.toString() ?? '';
  return [
    mealDisplayTitle(meal),
    meal['description']?.toString() ?? '',
    meal['category']?.toString() ?? '',
    tagText,
  ].join(' ').toLowerCase();
}

List<String> allergyTokens(String? raw) {
  return (raw ?? '')
      .toLowerCase()
      .split(RegExp(r'[,;/&+]|\band\b'))
      .map((token) => token.trim().replaceFirst(RegExp(r'^(no|without|not)\s+'), ''))
      .where((token) => token.length >= 3 || token == 'egg')
      .toList();
}

bool mealTitleLooksNonVegetarian(Map<String, dynamic>? meal) {
  final hay = mealDietHaystack(meal ?? const {});
  return RegExp(
    r'\b(egg|eggs|chicken|mutton|gosht|keema|fish|prawn|shrimp|meat|pork|bacon|ham|beef|non[- ]?veg)\b',
    caseSensitive: false,
  ).hasMatch(hay);
}

/// Green mark when veg. Accepts bool, 1/0, and "true"/"false" strings.
bool mealIsVegetarian(Map<String, dynamic>? meal) {
  if (meal == null) return true;
  final flag = meal['is_veg'] ?? meal['isVeg'];
  if (flag == true || flag == 1) return true;
  if (flag == false || flag == 0) return false;
  final text = flag?.toString().trim().toLowerCase() ?? '';
  if (text == 'true' || text == '1' || text == 'yes' || text == 'veg') return true;
  if (text == 'false' || text == '0' || text == 'no' || text.contains('non')) {
    return false;
  }
  return !mealTitleLooksNonVegetarian(meal);
}

bool mealMatchesDietaryPreference(Map<String, dynamic> meal, String? preference) {
  final pref = (preference ?? '').trim().toLowerCase();
  if (pref.isEmpty || pref == 'non-vegetarian' || pref == 'non vegetarian') return true;
  if (!mealIsVegetarian(meal)) return false;
  final haystack = mealDietHaystack(meal);
  if (pref == 'vegan') {
    return !_haystackHasAny(haystack, const [
      'dairy',
      'milk',
      'ghee',
      'butter',
      'paneer',
      'cheese',
      'curd',
      'egg',
      'honey',
    ]);
  }
  if (pref == 'jain') {
    return !_haystackHasAny(haystack, const [
      'onion',
      'garlic',
      'potato',
      'aloo',
      'ginger',
      'root',
    ]);
  }
  return true;
}

bool mealAvoidsAllergies(Map<String, dynamic> meal, String? allergies) {
  final tokens = allergyTokens(allergies);
  if (tokens.isEmpty) return true;
  final haystack = mealDietHaystack(meal);
  return !_haystackHasAny(haystack, tokens);
}

bool mealMatchesCustomerDiet(
  Map<String, dynamic> meal, {
  String? preference,
  String? allergies,
}) {
  return mealMatchesDietaryPreference(meal, preference) && mealAvoidsAllergies(meal, allergies);
}

const List<String> kFeedDietFilters = [
  'All',
  'Veg',
  'Vegan',
  'Jain',
  'High-protein',
  'Millet',
  'Diabetic',
];

const List<String> kChefDietTags = [
  'Jain',
  'High-protein',
  'Millet',
  'Diabetic',
];

String feedDietChipFromPreference(String? preference) {
  switch ((preference ?? '').trim().toLowerCase()) {
    case 'vegetarian':
    case 'veg':
      return 'Veg';
    case 'vegan':
      return 'Vegan';
    case 'jain':
      return 'Jain';
    default:
      return 'All';
  }
}

bool mealMatchesFeedDiet(Map<String, dynamic> meal, String? diet) {
  final selected = (diet ?? '').trim();
  if (selected.isEmpty || selected == 'All') return true;
  if (selected == 'Veg' || selected == 'Vegetarian') {
    return mealMatchesDietaryPreference(meal, 'Vegetarian');
  }
  if (selected == 'Vegan') return mealMatchesDietaryPreference(meal, 'Vegan');
  if (selected == 'Jain') return mealMatchesDietaryPreference(meal, 'Jain');

  final haystack = mealDietHaystack(meal);
  if (selected == 'High-protein') {
    return _haystackHasAny(haystack, const [
      'high-protein',
      'high protein',
      'protein-rich',
      'protein rich',
      'highprotein',
      'sprout',
      'soya',
      'soy chunk',
      'quinoa',
    ]);
  }
  if (selected == 'Millet') {
    return _haystackHasAny(haystack, const [
      'millet',
      'jowar',
      'bajra',
      'ragi',
      'nachni',
      'foxtail',
      'barnyard',
      'kodo',
    ]);
  }
  if (selected == 'Diabetic') {
    return _haystackHasAny(haystack, const [
      'diabetic',
      'diabetes',
      'sugar-free',
      'sugar free',
      'low gi',
      'low-gi',
      'no sugar',
      'unsweetened',
    ]);
  }
  return true;
}

List<String> cuisineAliases(String cuisine) {
  switch (cuisine.trim().toLowerCase()) {
    case 'north indian':
      return const ['north indian', 'north-indian', 'mughlai', 'tandoor'];
    case 'punjabi':
      return const ['punjabi', 'amritsari'];
    case 'south indian':
      return const ['south indian', 'south-indian', 'dosa', 'idli', 'sambar', 'uttapam', 'chettinad', 'andhra', 'kerala'];
    case 'maharashtrian':
      return const ['maharashtrian', 'maharashtra', 'malvani', 'kolhapuri', 'misal', 'thalipeeth', 'modak', 'sabudana'];
    case 'snacks':
      return const ['snack', 'snacks', 'chaat', 'pakora', 'samosa', 'farsan'];
    case 'desserts':
      return const ['dessert', 'desserts', 'sweet', 'mithai', 'halwa', 'kheer'];
    case 'healthy':
    case 'healthy & salads':
      return const ['healthy', 'salad', 'salads', 'bowl'];
    default:
      final value = cuisine.trim().toLowerCase();
      return value.isEmpty ? const [] : [value];
  }
}

bool mealMatchesCuisine(Map<String, dynamic> meal, String? cuisine) {
  final selected = (cuisine ?? '').trim();
  if (selected.isEmpty || selected == 'All') return true;
  if (selected.toLowerCase() == 'festival hamper') {
    return isFestivalHamper(meal);
  }
  if (selected.toLowerCase() == 'society night') {
    return isSocietyNight(meal);
  }
  if (selected.toLowerCase() == 'shelf' || selected.toLowerCase() == 'pantry') {
    return isShelfItem(meal);
  }
  final category = meal['category']?.toString().trim().toLowerCase() ?? '';
  final haystack = mealDietHaystack(meal);
  for (final alias in cuisineAliases(selected)) {
    if (alias.isEmpty) continue;
    if (category == alias || category.contains(alias) || haystack.contains(alias)) {
      return true;
    }
  }
  return false;
}

/// Favorites filter must turn off after logout — the Home tab stays alive.
bool feedFavoritesFilterActive({
  required bool signedIn,
  required bool favoritesOnly,
}) {
  return signedIn && favoritesOnly;
}

bool feedFollowingFilterActive({
  required bool signedIn,
  required bool followingOnly,
}) {
  return signedIn && followingOnly;
}

bool canFollowKitchen({String? viewerId, required String chefId}) {
  final kitchen = chefId.trim();
  if (kitchen.isEmpty) return false;
  final viewer = viewerId?.trim() ?? '';
  return viewer != kitchen;
}

class FeedEmptyCopy {
  const FeedEmptyCopy({
    required this.title,
    required this.message,
    this.promptSignIn = false,
    this.clearCategory = false,
  });

  final String title;
  final String message;
  final bool promptSignIn;
  final bool clearCategory;
}

FeedEmptyCopy feedEmptyCopy({
  required bool signedIn,
  required bool favoritesOnly,
  required bool hasFavorites,
  required bool hasSearch,
  String searchQuery = '',
  String category = 'All',
  String diet = 'All',
  bool hasDeliveryPin = false,
  bool followingOnly = false,
  bool hasFollows = false,
}) {
  final favorites = feedFavoritesFilterActive(signedIn: signedIn, favoritesOnly: favoritesOnly);
  final following = feedFollowingFilterActive(signedIn: signedIn, followingOnly: followingOnly);
  final categoryFilter = category != 'All';
  final dietFilter = diet != 'All';
  final filterLabel = [
    if (dietFilter) diet,
    if (categoryFilter) category,
  ].join(' ');
  final hasChipFilter = categoryFilter || dietFilter;

  if (!signedIn && followingOnly) {
    return const FeedEmptyCopy(
      title: 'Sign in to follow kitchens',
      message: 'Follow a home chef and we will ping you when their kitchen opens.',
      promptSignIn: true,
    );
  }
  if (following && !hasFollows) {
    return const FeedEmptyCopy(
      title: 'No kitchens followed yet',
      message: 'Tap a chef and follow the kitchen to get a ping when they open.',
    );
  }
  if (following) {
    return FeedEmptyCopy(
      title: hasChipFilter ? 'No $filterLabel meals from kitchens you follow' : 'No meals from kitchens you follow',
      message: 'Those kitchens are offline or sold out right now. We will ping you when they open.',
      clearCategory: hasChipFilter,
    );
  }
  if (!signedIn && favoritesOnly) {
    return const FeedEmptyCopy(
      title: 'Sign in to see favorites',
      message: 'Saved meals show up here after you sign in.',
      promptSignIn: true,
    );
  }
  if (favorites && !hasFavorites) {
    return const FeedEmptyCopy(
      title: 'No favorites yet',
      message: 'Tap the heart on a dish you love and it will land here.',
    );
  }
  if (favorites) {
    return FeedEmptyCopy(
      title: hasChipFilter ? 'No $filterLabel favorites' : 'No favorites on the menu',
      message: hasChipFilter
          ? 'None of your saved meals match $filterLabel right now. Try All or another chip.'
          : 'Your saved meals are not on the menu right now.',
      clearCategory: hasChipFilter,
    );
  }
  if (hasSearch) {
    final q = searchQuery.trim();
    return FeedEmptyCopy(
      title: 'No dishes or chefs found',
      message: q.isEmpty
          ? 'Try a different search.'
          : 'Nothing matched "$q". Try another dish name or home chef.',
    );
  }
  if (hasChipFilter) {
    return FeedEmptyCopy(
      title: 'No $filterLabel meals',
      message: hasDeliveryPin
          ? 'No $filterLabel kitchens are delivering to this pin right now. Try another chip or address.'
          : 'No $filterLabel dishes are on the menu right now. Try All or another chip.',
      clearCategory: true,
    );
  }
  return FeedEmptyCopy(
    title: 'No meals found',
    message: hasDeliveryPin
        ? 'No kitchens are delivering to this pin right now. Try another address or category.'
        : 'Try a different category or search for something else.',
  );
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

List<ChatInboxItem> mergeChatInboxRooms({
  required String myId,
  required List<Map<String, dynamic>> orders,
  required List<Map<String, dynamic>> requests,
  required List<Map<String, dynamic>> messages,
  Map<String, List<String>> quoteChefIdsByRequest = const {},
}) {
  final catalog = <String, ChatInboxItem>{};

  for (final order in orders) {
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
    if (existing != null) {
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
    } else {
      rooms[entry.key] = ChatInboxItem(
        roomId: entry.key,
        title: 'Chat',
        preview: preview,
        memberIds: const [],
        lastAt: DateTime.tryParse(message['created_at']?.toString() ?? ''),
        lastSenderId: message['sender_id']?.toString(),
        isGroup: false,
      );
    }
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

String formatFriendlyDate(DateTime date, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final target = DateTime(date.year, date.month, date.day);
  
  final diffDays = target.difference(today).inDays;
  if (diffDays == 0) return 'Today';
  if (diffDays == 1) return 'Tomorrow';
  if (diffDays == -1) return 'Yesterday';
  
  return formatAppDate(date);
}

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

/// Formats minutes-from-midnight as `h:mm AM/PM`.
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

/// Calendar day on promised slots, e.g. `Sep 9th 2026`.
String formatPromisedSlotDate(DateTime date) {
  final local = date.toLocal();
  return '${DateFormat('MMM').format(local)} ${local.day}${dayOrdinalSuffix(local.day)} ${local.year}';
}

/// Promised slot copy: `Sep 9th 2026, 10:00 AM to 11:00 AM`.
String formatPromisedSlotWindow(String? slot, {DateTime? onDate}) {
  final window = chefSlotWindowLabel(slot);
  if (window == 'ASAP') {
    return onDate == null ? 'ASAP' : '${formatPromisedSlotDate(onDate)}, ASAP';
  }
  if (onDate == null) {
    return window.startsWith('(') ? window : '($window)';
  }
  return '${formatPromisedSlotDate(onDate)}, $window';
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

/// Checkout copy: friendly day + chef hourly window.
String formatCheckoutDeliverySchedule({
  required String? slot,
  DateTime? scheduledDate,
  DateTime? now,
}) {
  return formatPromisedSlotWindow(slot, onDate: scheduledDate ?? now);
}

/// Compact kitchen window for meal cards (`9:00 AM–10:00 AM`).
String feedKitchenSlotLabel(String? timeSlot) {
  final window = chefSlotWindowLabel(timeSlot);
  if (window == 'ASAP') return 'On your slot';
  return window.replaceAll(' to ', '–');
}

String digitsOnlyPhone(String? raw) => (raw ?? '').replaceAll(RegExp(r'\D'), '');

/// Dummy / repeated digits that should never be used as a diner contact.
bool isPlaceholderPhone(String? raw) {
  final digits = digitsOnlyPhone(raw);
  if (digits.isEmpty) return true;
  if (digits == '1234567890' || digits == '0123456789') return true;
  if (digits.length >= 10 && RegExp(r'^(\d)\1+$').hasMatch(digits)) return true;
  return false;
}

String usableCustomerPhone(String? raw) {
  var digits = digitsOnlyPhone(raw);
  if (digits.length > 10) digits = digits.substring(digits.length - 10);
  if (isPlaceholderPhone(digits) || digits.length != 10) return '';
  return digits;
}

/// True when the selected slot's start is now or earlier on that calendar day.
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
  final tomorrow = tomorrowCalendarDay(now: current);
  final text = chefScheduleStr.trim();
  final servingDays = chefServingWeekdays(text);

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

  final tomorrowSlots = chefHourlySubSlots(text);
  if (tomorrowSlots.isNotEmpty) {
    return _chefSlotScheduleForDay(text: text, day: tomorrow, now: current, time: tomorrowSlots.first);
  }

  final clock = preferredChefSlotClock(text);
  if (clock == null || clock.isEmpty) {
    return _chefSlotScheduleForDay(text: text, day: today, now: current, time: text.isEmpty ? '' : text);
  }
  final startMins = clockTextToMinutes(clock);
  final nowMins = current.hour * 60 + current.minute;
  if (startMins != null && nowMins >= startMins) {
    return _chefSlotScheduleForDay(text: text, day: tomorrow, now: current, time: clock);
  }
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
  if (kitchenCoordinate(meal, latitude: true) == null ||
      kitchenCoordinate(meal, latitude: false) == null) {
    return true;
  }
  final address = (meal['hosting_address'] ?? meal['address'] ?? '').toString().trim();
  if (address.isEmpty) return true;
  return false;
}

bool mealHasPlaceholderOrMissingSlot(Map<String, dynamic> meal) {
  final slot = meal['time_slot']?.toString().trim() ?? '';
  if (slot.isEmpty || isImmediateDeliverySlot(slot)) return true;
  return !RegExp(r'\d{1,2}:\d{2}').hasMatch(slot);
}

const int kChefBoostRupees = 99;
const int kChefBoostPaise = 9900;

DateTime boostEndsAtLocalMidnight(DateTime now) {
  final local = now.toLocal();
  return DateTime(local.year, local.month, local.day + 1);
}

bool isMealBoosted(Map<String, dynamic>? meal, {DateTime? now}) {
  if (meal == null) return false;
  final until = DateTime.tryParse(meal['boosted_until']?.toString() ?? '');
  if (until == null) return false;
  return !until.toLocal().isBefore((now ?? DateTime.now()).toLocal());
}

String mealBoostUntilLabel(Map<String, dynamic>? meal, {DateTime? now}) {
  if (!isMealBoosted(meal, now: now)) return '';
  final until = DateTime.tryParse(meal?['boosted_until']?.toString() ?? '');
  if (until == null) return 'Boosted today';
  return 'Boosted until ${formatAppTime(until)}';
}

bool mealHasFlashableOffer(Map<String, dynamic> meal, {DateTime? now}) {
  if (!isCatalogMeal(meal) || !mealHasSellableStock(meal)) return false;
  if (mealFailsCurrentCatalogRequirements(meal)) return false;
  if (!isChefMenuActiveMeal(meal, now: now)) return false;
  if (!mealHasBookableSlotNow(meal, now: now)) return false;
  if (isMealBoosted(meal, now: now)) return true;
  final hasOffer = PricingCalculator.resolvedOfferType(meal) != OfferType.none;
  final hasPromo = PricingCalculator.mealPromoCode(meal) != null;
  if (!hasOffer && !hasPromo) return false;
  // Checkout still gates promo codes; Home lists every live family (BOGO, Flash, %, Flat).
  return PricingCalculator.isWithinOfferWindow(meal, referenceTime: now);
}

/// True when a diner can still book this plate on the current local day.
bool mealHasBookableSlotNow(Map<String, dynamic> meal, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toLocal();
  final slot = meal['time_slot']?.toString();
  final days = chefServingWeekdays(slot);
  if (days != null && days.isNotEmpty && !days.contains(n.weekday)) return false;
  if (isChefMealArchived(meal)) return false;
  if (slot == null || slot.trim().isEmpty || isImmediateDeliverySlot(slot)) return false;
  final labeledDay = parseSlotCalendarDay(slot, now: n);
  final selected = DateTime.tryParse(meal['selected_date']?.toString() ?? '');
  final day = selected ?? labeledDay;
  if (day != null && calendarDay(day).isBefore(calendarDay(n))) return false;
  final remaining = futureChefSubSlots(slot, scheduledDate: calendarDay(n), now: n);
  if (remaining.isNotEmpty) return true;
  final clocks =
      RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).allMatches(slot).toList();
  if (clocks.isEmpty) return true;
  final end = parseClockOnDate(
    (clocks.length >= 2 ? clocks[1] : clocks.first).group(0)!,
    calendarDay(n),
  );
  if (end == null) return true;
  return n.isBefore(end);
}

List<Map<String, dynamic>> flashableOfferMeals(
  Iterable<Map<String, dynamic>> meals, {
  Set<String> excludedChefIds = const {},
  DateTime? now,
  int limit = 8,
  double? destinationLat,
  double? destinationLng,
  Map<String, Map<String, dynamic>> chefKitchenPins = const {},
}) {
  final unique = <String>{};
  final offers = <Map<String, dynamic>>[];
  for (final meal in meals) {
    final chefId = meal['chef_id']?.toString() ?? '';
    if (chefId.isNotEmpty && excludedChefIds.contains(chefId)) continue;
    if (!mealHasFlashableOffer(meal, now: now)) continue;
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
    offers.add(pinned);
  }
  offers.sort((a, b) {
    final aBoosted = isMealBoosted(a, now: now);
    final bBoosted = isMealBoosted(b, now: now);
    if (aBoosted != bBoosted) return aBoosted ? -1 : 1;
    return 0;
  });

  // One carousel card per offer family — tap opens every matching plate.
  const groupOrder = <String>[
    'festive',
    'flashSale',
    'bogo',
    'percentage',
    'flat',
  ];
  final buckets = <String, List<Map<String, dynamic>>>{
    for (final key in groupOrder) key: <Map<String, dynamic>>[],
  };
  final rest = <Map<String, dynamic>>[];

  for (final meal in offers) {
    final key = offerFlashGroupKeyForMeal(meal);
    if (key != null && buckets.containsKey(key)) {
      buckets[key]!.add(meal);
    } else {
      rest.add(meal);
    }
  }

  final collapsed = <Map<String, dynamic>>[];
  for (final key in groupOrder) {
    final group = buckets[key]!;
    if (group.isEmpty) continue;
    collapsed.add(buildOfferFlashGroupCard(key, group));
  }
  collapsed.addAll(rest);

  if (collapsed.length <= limit) return collapsed;
  return collapsed.sublist(0, limit);
}

/// Carousel group key for a live meal (festive hampers win over offer_type).
String? offerFlashGroupKeyForMeal(Map<String, dynamic> meal) {
  if (isFestivalHamper(meal)) return 'festive';
  final type = OfferType.fromString(meal['offer_type']?.toString());
  switch (type) {
    case OfferType.bogo:
      return 'bogo';
    case OfferType.flashSale:
      return 'flashSale';
    case OfferType.percentage:
      return 'percentage';
    case OfferType.flat:
      return 'flat';
    case OfferType.none:
      return null;
  }
}

Map<String, dynamic> buildOfferFlashGroupCard(String groupKey, List<Map<String, dynamic>> meals) {
  Map<String, dynamic> rep = Map<String, dynamic>.from(meals.first);
  for (final meal in meals) {
    if ((meal['image_url']?.toString() ?? '').trim().isNotEmpty) {
      rep = Map<String, dynamic>.from(meal);
      break;
    }
  }
  rep['_offer_group'] = groupKey;
  rep['_offer_group_count'] = meals.length;
  // Back-compat for older BOGO-only callers.
  if (groupKey == 'bogo') {
    rep['_bogo_group'] = true;
    rep['_bogo_count'] = meals.length;
  }
  return rep;
}

String offerFlashGroupLabel(String? groupKey) {
  switch (groupKey) {
    case 'festive':
      return 'Festive';
    case 'flashSale':
      return 'Flash Sale';
    case 'bogo':
      return 'BOGO';
    case 'percentage':
      return '% Discount';
    case 'flat':
      return 'Flat Discount';
    default:
      return 'Offers';
  }
}

String offerFlashGroupBrowseHint(String? groupKey) {
  switch (groupKey) {
    case 'festive':
      return 'All festive / hamper plates near you';
    case 'flashSale':
      return 'All Flash Sale plates near you';
    case 'bogo':
      return 'All Buy 1 Get 1 plates near you';
    case 'percentage':
      return 'All % discount plates near you';
    case 'flat':
      return 'All flat ₹ discount plates near you';
    default:
      return 'Matching offer plates near you';
  }
}

String? offerFlashGroupKey(Map<String, dynamic> meal) {
  final grouped = meal['_offer_group']?.toString().trim();
  if (grouped != null && grouped.isNotEmpty) return grouped;
  if (meal['_bogo_group'] == true) return 'bogo';
  return null;
}

String offerFlashHeadline(Map<String, dynamic> meal, {DateTime? now}) {
  final group = offerFlashGroupKey(meal);
  if (group != null) {
    switch (group) {
      case 'festive':
        return 'Festive offers';
      case 'flashSale':
        return 'Flash Sale';
      case 'bogo':
        return 'BOGO';
      case 'percentage':
        return '% Discount';
      case 'flat':
        return 'Flat Discount';
    }
  }
  if (isMealBoosted(meal, now: now) && PricingCalculator.mealPromoCode(meal) == null) {
    return 'Boosted today';
  }
  final code = PricingCalculator.mealPromoCode(meal);
  if (code != null && PricingCalculator.isOfferGated(meal)) {
    return 'Use $code';
  }
  final badge = PricingCalculator.offerBadgeLabel(meal).trim();
  if (code != null && badge.isNotEmpty) return '$badge · $code';
  if (code != null) return code;
  return badge.isEmpty ? "Today's offer" : badge;
}

String offerFlashSubhead(Map<String, dynamic> meal) {
  final group = offerFlashGroupKey(meal);
  if (group != null) {
    final count = int.tryParse(meal['_offer_group_count']?.toString() ?? meal['_bogo_count']?.toString() ?? '') ?? 0;
    final label = offerFlashGroupLabel(group);
    if (count > 1) return '$count plates · tap to see all $label deals';
    return '$label · tap to browse';
  }
  final type = OfferType.fromString(meal['offer_type']?.toString());
  if (type != OfferType.none) {
    return '${offerFlashGroupLabel(offerFlashGroupKeyForMeal(meal))} · tap to see all matching plates';
  }
  if (isFestivalHamper(meal)) {
    return 'Festive · tap to see all festive plates';
  }
  final title = meal['title']?.toString().trim() ?? meal['name']?.toString().trim() ?? '';
  return title.isEmpty ? 'Tap to see this kitchen special' : title;
}

bool isFestivalHamper(Map<String, dynamic>? meal) {
  if (meal == null) return false;
  final flag = meal['is_hamper'] ?? meal['isHamper'];
  if (flag == true) return true;
  if (flag == false || flag == null) {
    final category = meal['category']?.toString().trim().toLowerCase() ?? '';
    final title = meal['title']?.toString().trim().toLowerCase() ?? '';
    final tags = '${meal['health_tags'] ?? meal['tags'] ?? ''}'.toLowerCase();
    return category.contains('hamper') ||
        category.contains('festival') ||
        title.contains('hamper') ||
        tags.contains('hamper');
  }
  final text = flag.toString().toLowerCase().trim();
  return text == 'true' || text == '1' || text == 'yes';
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

bool isSocietyNight(Map<String, dynamic>? meal) {
  if (meal == null) return false;
  if (_truthyFlag(meal['is_society_night'] ?? meal['isSocietyNight'])) return true;
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
  if (_truthyFlag(meal['is_shelf_item'] ?? meal['isShelfItem'])) return true;
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

String rescuedMealsHeadline({required int rescuedPlates, required int onOfferPlates}) {
  if (rescuedPlates > 0) {
    final plateWord = rescuedPlates == 1 ? 'plate' : 'plates';
    return 'Saved from waste · $rescuedPlates $plateWord pre-ordered';
  }
  if (onOfferPlates > 0) {
    final plateWord = onOfferPlates == 1 ? 'meal' : 'meals';
    return '$onOfferPlates slotted $plateWord ready to pre-order';
  }
  return 'Pre-order a slot — kitchens cook only what you book';
}

String rescuedMealsSubhead({required int rescuedPlates, required int onOfferPlates}) {
  if (rescuedPlates > 0 && onOfferPlates > 0) {
    return 'Chefs cook to booked demand. $onOfferPlates more slots open now.';
  }
  if (rescuedPlates > 0) {
    return 'Neighbours booked ahead so home kitchens cooked only what was needed.';
  }
  if (onOfferPlates > 0) {
    return 'Book a time slot. Fresh food, no guesswork leftovers.';
  }
  return 'HotPotChef is pre-order first — less waste than cooking on hope.';
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

/// Parses a calendar day from labels like "Sun, 18th Aug at 9:30 AM".
DateTime? parseSlotCalendarDay(String? raw, {DateTime? now}) {
  if (raw == null || raw.trim().isEmpty) return null;
  final n = (now ?? DateTime.now()).toLocal();
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
    return 'This kitchen just went offline. Your payment was refunded and should return in 5–7 business days.';
  }
  if (charged) {
    return 'This kitchen just went offline after payment. We are issuing a refund.';
  }
  return 'This kitchen just went offline. Nothing was charged — try another chef or come back later.';
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

String soldOutCheckoutMessage({required bool charged, bool refunded = false}) {
  if (charged && refunded) {
    return 'This meal just sold out. Your payment was refunded and should return in 5–7 business days.';
  }
  if (charged) {
    return 'This meal just sold out after payment. We are issuing a refund.';
  }
  return 'This meal just sold out. Nothing was charged — pick another portion or chef.';
}

String checkoutErrorMessage(Object error) {
  var text = networkErrorMessage(error).trim();
  if (text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length);
  }
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
  return double.tryParse(value?.toString() ?? '') ?? fallback;
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
      status.contains('deliver') ||
      status.contains('fulfill') ||
      status.contains('complete')) {
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
  final name = (tier ?? '').toLowerCase();
  if (name.contains('gold')) return 0;
  return kDefaultPackagingFee;
}

/// Shelf-only carts: ₹0. Hamper-only: capped gift wrap. Hot meals: loyalty packaging.
double packagingFeeForCartItems(
  Iterable<Map<String, dynamic>> items, {
  String? loyaltyTier,
  double? loyaltyTierFee,
}) {
  final base = loyaltyTierFee ?? packagingFeeForLoyaltyTier(loyaltyTier);
  final list = items.toList();
  if (list.isEmpty) return base;

  var hot = 0;
  var hamper = 0;
  var shelf = 0;
  for (final item in list) {
    final nested = item['rawMealDetails'] ?? item['mealDetails'] ?? item['meal_details'];
    final merged = {
      if (nested is Map) ...Map<String, dynamic>.from(nested),
      ...item,
    };
    if (isShelfItem(merged)) {
      shelf += 1;
    } else if (isFestivalHamper(merged)) {
      hamper += 1;
    } else {
      hot += 1;
    }
  }

  if (hot > 0) return base;
  if (shelf > 0 && hamper == 0) return 0;
  if (hamper > 0) return base < 10 ? base : 10;
  return base;
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
    if (status.contains('deliver') || status.contains('complet')) count++;
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

/// Unit price for a cart/order line. Ignores a "discount" that is higher than the listed price.
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

/// Chefs may start cooking once the requested drop-off is this close.
const int kChefPrepEarliestMinutes = 120;

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
  if (slotHasClockRange(rawSlot)) {
    return formatPromisedSlotWindow(rawSlot, onDate: slotDay);
  }
  return smartTimeSlot(
    rawSlot.isEmpty ? 'ASAP' : rawSlot,
    placed,
    selectedDateStr: selectedDateStr.isEmpty ? null : selectedDateStr,
  );
}

/// Start Preparing unlocks at 120 minutes before the requested time, and stays
/// on through the last hour and after the slot (food must still go out).
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
    return 'Opens 2 hours before the requested time';
  }
  return 'Opens in $wait (2 hours before requested time)';
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
  final start = orderSlotStart(order, now: now);
  if (start == null) return false;
  return start.isBefore(now ?? DateTime.now());
}

/// Diner-facing promised slot, e.g. "Arriving by 8:00 PM · 12 min left".
String dinerPromisedSlotCopy(Map<String, dynamic> order, {DateTime? now, String? status}) {
  if (!dinerSlotCountdownActive(status ?? order['status']?.toString())) return '';
  final slot = formatDeliverySlotLabel(order, now: now);
  final tick = formatSlotCountdown(orderSlotStart(order, now: now), now: now);
  if (tick.isEmpty) {
    return slot == 'ASAP' ? 'Arriving ASAP' : 'Arriving by $slot';
  }
  if (tick == 'Due now') return 'Due now · arriving by $slot';
  if (tick.contains('late')) return '$tick · promised $slot';
  return 'Arriving by $slot · $tick';
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
  final packaging = parseMoney(source['packaging_fee'], 20);
  final tip = parseMoney(source['tip_amount'] ?? source['tip']);
  var coins = parseMoney(source['coins_applied']);
  final storedDelivery = double.tryParse(source['delivery_fee']?.toString() ?? '');

  final service = (source['order_type'] ?? source['service_type'] ?? '').toString().toLowerCase();
  final deliveryExpected = hasDelivery || service.contains('delivery');

  double delivery;
  if (!deliveryExpected) {
    delivery = storedDelivery ?? 0;
  } else if (storedDelivery != null) {
    delivery = storedDelivery;
  } else if (paidTotal > 0) {
    delivery = paidTotal - itemsTotal - packaging - tip + coins;
    if (delivery < 0) delivery = 0;
  } else {
    delivery = 30;
  }

  final extras = packaging + delivery + tip;
  // Older rows stored food-only in total_price (e.g. ₹221) while packaging still applies.
  final paidLooksLikeItemsOnly =
      paidTotal > 0 && (paidTotal - itemsTotal).abs() < 0.5 && extras >= 0.5;

  if (!paidLooksLikeItemsOnly && coins <= 0 && paidTotal > 0) {
    final implied = itemsTotal + packaging + delivery + tip - paidTotal;
    if (implied >= 0.5) coins = implied;
  }

  final computed = (itemsTotal + packaging + delivery + tip - coins).clamp(0, double.infinity);
  final grand = (paidTotal > 0 && !paidLooksLikeItemsOnly) ? paidTotal : computed;

  return OrderBillBreakdown(
    itemsTotal: itemsTotal,
    packagingFee: packaging,
    deliveryFee: delivery,
    tipAmount: tip,
    coinsApplied: coins,
    grandTotal: grand.toDouble(),
    itemsGross: itemsGross,
    promoDiscount: promoDiscount,
    promoLabel: promoLabel,
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
}) {
  if (lat != null && lng != null && lat != 0 && lng != 0) {
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
  }
  final text = (address ?? '').trim();
  if (text.isEmpty) return null;
  return Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(text)}&travelmode=driving',
  );
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
/// Meals without a kitchen pin stay visible (same as feed unknown-pin behavior).
bool mealInDeliveryRadius(
  Map<String, dynamic> meal, {
  double? destinationLat,
  double? destinationLng,
  double maxRoadKm = 15,
  double roadMultiplier = 1.3,
}) {
  if (destinationLat == null || destinationLng == null) return true;
  if (destinationLat == 0 || destinationLng == 0) return true;
  final startLat = kitchenCoordinate(meal, latitude: true);
  final startLng = kitchenCoordinate(meal, latitude: false);
  if (startLat == null || startLng == null) return true;
  final roadKm = haversineKm(startLat, startLng, destinationLat, destinationLng) * roadMultiplier;
  return roadKm <= maxRoadKm;
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

Map<String, dynamic>? preferredCheckoutAddress(
  List<Map<String, dynamic>> addresses, {
  Object? selectedId,
  Map<String, dynamic>? hint,
}) {
  if (addresses.isEmpty) return null;
  if (selectedId != null) {
    for (final address in addresses) {
      if (address['id']?.toString() == selectedId.toString()) return address;
    }
  }
  if (hint != null) {
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

  for (final txn in transactions) {
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
      orderRef = formatOrderId(orderRef, orderRef);
      for (final o in orders) {
        final ref = formatOrderId(o['order_id']?.toString(), o['id']?.toString() ?? '');
        if (ref == orderRef) {
          matchedOrder = o;
          break;
        }
      }
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