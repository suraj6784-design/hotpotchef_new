// lib/utils/helpers.dart

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'network.dart';
import 'notification_copy.dart';

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

String mealShareUri(String? mealId) {
  final id = mealId?.trim() ?? '';
  if (id.isEmpty) return '';
  return 'hotpotchef://app/meal/$id';
}

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

String? normalizeReferralCode(String? raw) {
  final code = (raw ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  return code.isEmpty ? null : code;
}

bool isPlausibleReferralCode(String code) {
  return RegExp(r'^[A-Z0-9]{6,16}$').hasMatch(code);
}

String referralInviteText(String code) {
  return "Craving authentic home-cooked food? Join HotPotChef and enter my code $code when you sign up to get 50 HotPot Coins on your first order.";
}

Map<String, dynamic> signupUserPayload({
  required String id,
  required String email,
  required String name,
  required String phone,
  required String role,
  String? referredBy,
  String? createdAt,
}) {
  return {
    'id': id,
    'email': email,
    'name': name,
    'full_name': name,
    'phone': phone,
    'role': role,
    if (createdAt != null) 'created_at': createdAt,
    if (referredBy != null) 'referred_by': referredBy,
  };
}

String mealShareText(Map<String, dynamic> meal) {
  final title = mealDisplayTitle(meal);
  final chef = chefDisplayName(meal);
  final price = parseMoney(meal['discounted_price'] ?? meal['price']);
  final priceBit = price > 0 ? ' — ₹${price.toStringAsFixed(0)}' : '';
  final link = mealShareUri(meal['id']?.toString() ?? mealIdFromOrderItem(meal));
  return link.isEmpty
      ? 'Try $title from $chef on HotPotChef$priceBit'
      : 'Try $title from $chef on HotPotChef$priceBit\n$link';
}

String formatOrderId(String? rawOrderId, String fallbackId) {
  if (rawOrderId != null && rawOrderId.isNotEmpty) {
    return rawOrderId.length > 8 ? rawOrderId.substring(0, 8).toUpperCase() : rawOrderId.toUpperCase();
  }
  return fallbackId.length > 8 ? fallbackId.substring(0, 8).toUpperCase() : fallbackId.toUpperCase();
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

bool mealMatchesDietaryPreference(Map<String, dynamic> meal, String? preference) {
  final pref = (preference ?? '').trim().toLowerCase();
  if (pref.isEmpty || pref == 'non-vegetarian' || pref == 'non vegetarian') return true;
  if (meal['is_veg'] == false) return false;
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

/// Favorites filter must turn off after logout — the Home tab stays alive.
bool feedFavoritesFilterActive({
  required bool signedIn,
  required bool favoritesOnly,
}) {
  return signedIn && favoritesOnly;
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
  bool hasDeliveryPin = false,
}) {
  final favorites = feedFavoritesFilterActive(signedIn: signedIn, favoritesOnly: favoritesOnly);
  final categoryFilter = category != 'All';

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
      title: categoryFilter ? 'No $category favorites' : 'No favorites on the menu',
      message: categoryFilter
          ? 'None of your saved meals are in $category right now. Try All or another category.'
          : 'Your saved meals are not on the menu right now.',
      clearCategory: categoryFilter,
    );
  }
  if (hasSearch) {
    final q = searchQuery.trim();
    return FeedEmptyCopy(
      title: 'No meals found',
      message: q.isEmpty ? 'Try a different search.' : 'Nothing matched "$q". Try another dish or category.',
    );
  }
  if (categoryFilter) {
    return FeedEmptyCopy(
      title: 'No $category meals',
      message: hasDeliveryPin
          ? 'No $category kitchens are delivering to this pin right now. Try another category or address.'
          : 'No $category dishes are on the menu right now. Try All or another category.',
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
  return route.startsWith('/chat/') || route.startsWith('/meal/');
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

List<ChatInboxItem> mergeChatInboxRooms({
  required String myId,
  required List<Map<String, dynamic>> orders,
  required List<Map<String, dynamic>> requests,
  required List<Map<String, dynamic>> messages,
}) {
  final rooms = <String, ChatInboxItem>{};

  for (final order in orders) {
    final roomId = orderChatRoomId(order);
    if (roomId.isEmpty) continue;
    final label = formatOrderId(order['order_id']?.toString() ?? order['id']?.toString(), roomId);
    final members = orderChatMemberIds(order).toList();
    final other = members.firstWhere((id) => id != myId, orElse: () => '');
    rooms[roomId] = ChatInboxItem(
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
    final members = <String>{
      if ((request['customer_id']?.toString() ?? '').isNotEmpty) request['customer_id'].toString(),
      if ((request['accepted_chef_id']?.toString() ?? '').isNotEmpty) request['accepted_chef_id'].toString(),
    }.toList();
    final other = members.firstWhere((id) => id != myId, orElse: () => '');
    final title = request['title']?.toString().trim();
    rooms[roomId] = ChatInboxItem(
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

  for (final entry in latest.entries) {
    final message = entry.value;
    final existing = rooms[entry.key];
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

bool isMealAvailableForCart(Map<String, dynamic> meal) {
  final qty = int.tryParse(meal['quantity']?.toString() ?? '0') ?? 0;
  final status = meal['status']?.toString().toLowerCase().trim() ?? '';
  if (qty <= 0) return false;
  if (status == 'sold out' || status == 'paused' || status == 'unavailable') return false;
  return !isMealExpired(meal['time_slot']?.toString());
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

String checkoutErrorMessage(Object error) {
  var text = networkErrorMessage(error).trim();
  if (text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length);
  }
  return text;
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

/// Keeps only JSON-safe checkout fields so paid-order recording cannot fail on meal blobs.
List<Map<String, dynamic>> checkoutCartPayload(List<Map<String, dynamic>> items) {
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
    return {
      'chef_id': chefId,
      'chefId': chefId,
      'chef_name': chefDisplayName({...nestedMap, ...item}),
      'meal_id': mealId,
      'source_meal_id': mealId,
      'title': item['title'] ?? item['name'] ?? nestedMap['title'],
      'quantity': item['quantity'] ?? 1,
      'price': item['price'] ?? item['base_price'] ?? item['basePrice'] ?? nestedMap['price'],
      'base_price': item['base_price'] ?? item['basePrice'] ?? item['price'] ?? nestedMap['price'],
      'discounted_price': item['discounted_price'] ?? item['discountedPrice'] ?? nestedMap['discounted_price'],
      'selected_service_type': item['selected_service_type'] ?? item['service_type'] ?? item['serviceType'],
      'service_type': item['service_type'] ?? item['selected_service_type'] ?? item['serviceType'],
      'time_slot': item['time_slot'] ?? item['timeSlot'] ?? nestedMap['exact_time'] ?? nestedMap['time_slot'],
      'selected_date': item['selected_date'] ?? item['selectedDate'] ?? item['scheduled_date'],
      'selectedAddOns': _jsonSafeValue(item['selectedAddOns'] ?? item['selected_add_ons'] ?? const []),
    };
  }).toList();
}

double parseMoney(dynamic value, [double fallback = 0]) {
  return double.tryParse(value?.toString() ?? '') ?? fallback;
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

/// Unit price for a cart/order line. Ignores a "discount" that is higher than the listed price.
double lineItemUnitPrice(Map<String, dynamic> item) {
  final unit = parseMoney(item['price'] ?? item['unit_price'] ?? item['base_price'] ?? item['basePrice']);
  final discounted = parseMoney(item['discounted_price'] ?? item['discountedPrice']);
  if (discounted > 0 && (unit <= 0 || discounted <= unit + 0.001)) {
    return discounted;
  }
  return unit;
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

DateTime? parseClockOnDate(String timeText, DateTime date) {
  final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).firstMatch(timeText);
  if (match == null) return null;
  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final ampm = match.group(3)!.toUpperCase();
  if (ampm == 'PM' && hour != 12) hour += 12;
  if (ampm == 'AM' && hour == 12) hour = 0;
  return DateTime(date.year, date.month, date.day, hour, minute);
}

/// Start of the scheduled slot, used to stop customer cancel once the window begins.
DateTime? orderSlotStart(Map<String, dynamic> order, {DateTime? now}) {
  final placed = DateTime.tryParse(order['created_at']?.toString() ?? '')?.toLocal() ?? now;
  final rawSlot = order['time_slot']?.toString() ??
      order['delivery_slot']?.toString() ??
      order['selected_slot']?.toString() ??
      '';
  if (rawSlot.isEmpty && placed == null) return null;
  final slot = smartTimeSlot(
    rawSlot.isEmpty ? null : rawSlot,
    placed ?? DateTime.now(),
    selectedDateStr: order['selected_date']?.toString(),
  );
  final assumedYear = (placed ?? DateTime.now()).year;
  final date = parseSlotDate(slot, assumedYear) ??
      (placed != null ? DateTime(placed.year, placed.month, placed.day) : null);
  if (date == null) return null;
  return parseClockOnDate(slot, date) ?? DateTime(date.year, date.month, date.day);
}

String formatDeliverySlotLabel(Map<String, dynamic> order, {DateTime? now}) {
  final placed = DateTime.tryParse(order['created_at']?.toString() ?? '')?.toLocal() ?? now ?? DateTime.now();
  final rawSlot = order['time_slot']?.toString() ??
      order['delivery_slot']?.toString() ??
      order['selected_slot']?.toString() ??
      '';
  return smartTimeSlot(
    rawSlot.isEmpty ? 'ASAP' : rawSlot,
    placed,
    selectedDateStr: order['selected_date']?.toString(),
  );
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
  });

  final double itemsTotal;
  final double packagingFee;
  final double deliveryFee;
  final double tipAmount;
  final double coinsApplied;
  final double grandTotal;
}

/// Builds the bill from the stored paid total when present, instead of a hardcoded delivery fee.
OrderBillBreakdown orderBillBreakdown({
  required List<Map<String, dynamic>> items,
  Map<String, dynamic>? order,
  bool hasDelivery = false,
}) {
  final source = order ?? (items.isNotEmpty ? items.first : const <String, dynamic>{});

  var itemsTotal = 0.0;
  for (final item in items) {
    final price = lineItemUnitPrice(item);
    final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
    itemsTotal += price * qty;
  }

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
  );
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
    data['house_no'],
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

/// Builds a checkout payload from a claimed catering / bulk request.
List<Map<String, dynamic>> checkoutItemsFromCateringRequest(Map<String, dynamic> request) {
  final quantity = int.tryParse(request['quantity']?.toString() ?? '1') ?? 1;
  final budget = parseMoney(request['budget']);
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