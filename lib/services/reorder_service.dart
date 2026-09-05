import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_enums.dart';
import '../providers/cart_provider.dart';
import '../utils/helpers.dart';

class ReorderResult {
  final int added;
  final List<String> skipped;
  final List<String> alternatives;

  const ReorderResult({
    required this.added,
    this.skipped = const [],
    this.alternatives = const [],
  });
}

const List<String> kWeekdayFull = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

bool isSuccessfulPastOrder(Map<String, dynamic>? order) {
  final status = order?['status']?.toString().toLowerCase() ?? '';
  return status.contains('deliver') || status.contains('complet');
}

List<Map<String, dynamic>> orderItemsForReorder(Map<String, dynamic>? order) {
  if (order == null) return const [];
  return parseOrderItemsList(order['items'] ?? order['cart_items'] ?? order['order_items']);
}

Map<String, dynamic>? lastSuccessfulOrder(Iterable<dynamic> rows) {
  for (final row in rows) {
    if (row is! Map) continue;
    final order = Map<String, dynamic>.from(row);
    if (!isSuccessfulPastOrder(order)) continue;
    if (orderItemsForReorder(order).isEmpty) continue;
    return order;
  }
  return null;
}

String reorderMealSummary(List<Map<String, dynamic>> items) {
  if (items.isEmpty) return 'Your last order';
  final first = items.first['title']?.toString() ?? items.first['name']?.toString() ?? 'Meal';
  if (items.length == 1) return first;
  return '$first + ${items.length - 1} more';
}

String sameAsLastLabel(DateTime? placed, {DateTime? now}) {
  if (placed == null) return 'Order again';
  final current = (now ?? DateTime.now()).toLocal();
  final local = placed.toLocal();
  final days = DateTime(current.year, current.month, current.day)
      .difference(DateTime(local.year, local.month, local.day))
      .inDays;
  if (days < 0) return 'Order again';
  if (days == 0) return 'Same as earlier today';
  if (days == 1) return 'Same as yesterday';
  if (days < 7) {
    final weekday = kWeekdayFull[(local.weekday - 1).clamp(0, 6)];
    return 'Same as last $weekday';
  }
  return 'Order again';
}

String? catalogMealIdFromOrderItem(Map<String, dynamic>? item) {
  if (item == null) return null;
  for (final key in const ['source_meal_id', 'meal_id', 'mealId']) {
    final value = item[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return null;
}

bool orderItemsAlreadyInCart(List<Map<String, dynamic>> items, Iterable<String> cartMealIds) {
  final ids = items.map(catalogMealIdFromOrderItem).whereType<String>().where((id) => id.isNotEmpty).toSet();
  if (ids.isEmpty) return false;
  final inCart = cartMealIds.toSet();
  return ids.every(inCart.contains);
}

class ReorderService {
  ReorderService._();

  static List<CartItemAddOn> parseMealAddOns(dynamic raw) {
    dynamic decoded = raw;
    if (decoded is String && decoded.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((row) {
          final map = Map<String, dynamic>.from(row);
          return CartItemAddOn(
            id: map['id']?.toString() ?? map['title']?.toString() ?? '',
            title: map['title']?.toString() ?? map['name']?.toString() ?? 'Add-on',
            price: (map['price'] as num?)?.toDouble() ??
                double.tryParse(map['price']?.toString() ?? '0') ??
                0,
          );
        })
        .where((addon) => addon.title.isNotEmpty)
        .toList();
  }

  static bool isMealReorderable(Map<String, dynamic>? meal) {
    if (meal == null) return false;
    final status = meal['status']?.toString().toLowerCase().trim() ?? '';
    if (status.contains('sold') || status == 'paused' || status == 'cancelled') return false;
    final stock = int.tryParse(meal['quantity']?.toString() ?? '0') ?? 0;
    return stock > 0;
  }

  static Future<ReorderResult> addOrderItemsToCart({
    required CartNotifier cart,
    required List<Map<String, dynamic>> items,
    bool clearIfVendorConflict = true,
  }) async {
    if (items.isEmpty) return const ReorderResult(added: 0);

    var added = 0;
    var allowClear = clearIfVendorConflict;
    final skipped = <String>[];
    final seenMealIds = <String>{};
    final chefIds = <String>{};
    final kitchenOpen = <String, bool>{};
    String? dietPref;
    String? allergies;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final prefs = await Supabase.instance.client
            .from('users')
            .select('dietary_preference, allergies')
            .eq('id', user.id)
            .maybeSingle();
        dietPref = prefs?['dietary_preference']?.toString();
        allergies = prefs?['allergies']?.toString();
      }
    } catch (_) {}

    try {
      final ids = items
          .map((item) => item['chef_id']?.toString() ?? item['chefId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isNotEmpty) {
        final rows = await Supabase.instance.client
            .from('chef_profiles')
            .select('user_id, is_open')
            .inFilter('user_id', ids);
        for (final row in rows) {
          kitchenOpen[row['user_id'].toString()] = isChefKitchenOpen(Map<String, dynamic>.from(row));
        }
      }
    } catch (_) {}

    for (final item in items) {
      final title = item['title']?.toString() ?? item['name']?.toString() ?? 'Meal';
      final mealId = mealIdFromOrderItem(item);
      Map<String, dynamic>? liveMeal;

      if (mealId != null) {
        try {
          final live = await Supabase.instance.client
              .from('meals')
              .select()
              .eq('id', mealId)
              .maybeSingle();
          if (live != null) liveMeal = Map<String, dynamic>.from(live);
        } catch (_) {}
      }

      if (mealId != null) seenMealIds.add(mealId);

      if (mealId != null && liveMeal == null) {
        final chefId = item['chef_id']?.toString() ?? '';
        if (chefId.isNotEmpty) chefIds.add(chefId);
        skipped.add(title);
        continue;
      }

      final meal = liveMeal ??
          {
            ...item,
            'id': ?mealId,
            'title': title,
            'price': item['price'] ?? item['base_price'] ?? item['unit_price'] ?? 0,
            'chef_id': item['chef_id'],
            'quantity': item['max_quantity'] ?? item['available_quantity'] ?? 99,
          };

      final chefId = meal['chef_id']?.toString() ?? item['chef_id']?.toString() ?? '';
      if (chefId.isNotEmpty) chefIds.add(chefId);

      if (chefId.isNotEmpty && kitchenOpen[chefId] == false) {
        skipped.add('$title (kitchen closed)');
        continue;
      }

      if (!isMealReorderable(meal)) {
        skipped.add(title);
        continue;
      }

      final dietReason = dietSkipReason(
        meal,
        preference: dietPref,
        allergies: allergies,
        title: title,
      );
      if (dietReason != null) {
        skipped.add(dietReason);
        continue;
      }

      final available = int.tryParse(meal['quantity']?.toString() ?? '1') ?? 1;
      final requested = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
      final qty = requested.clamp(1, available);
      final addOns = parseMealAddOns(
        item['selectedAddOns'] ?? item['selected_add_ons'] ?? item['add_ons'],
      );

      final ok = cart.addToCart(
        meal,
        qty,
        addOns: addOns,
        clearIfVendorConflict: allowClear,
      );
      if (ok) {
        added += 1;
        allowClear = false;
      } else {
        skipped.add(title);
      }
    }

    var alternatives = const <String>[];
    if (skipped.isNotEmpty && chefIds.isNotEmpty) {
      alternatives = await _loadAlternatives(chefIds: chefIds, excludeMealIds: seenMealIds);
    }

    return ReorderResult(added: added, skipped: skipped, alternatives: alternatives);
  }

  static List<String> alternativeTitles(
    List<Map<String, dynamic>> liveMeals, {
    Set<String> excludeMealIds = const {},
    int limit = 3,
  }) {
    final titles = <String>[];
    for (final meal in liveMeals) {
      if (!isMealReorderable(meal)) continue;
      final id = meal['id']?.toString() ?? '';
      if (id.isNotEmpty && excludeMealIds.contains(id)) continue;
      final title = meal['title']?.toString() ?? meal['name']?.toString() ?? '';
      if (title.isEmpty || titles.contains(title)) continue;
      titles.add(title);
      if (titles.length >= limit) break;
    }
    return titles;
  }

  static String resultMessage(ReorderResult result) {
    final alt = result.alternatives.isEmpty ? '' : ' Try: ${result.alternatives.join(', ')}.';
    if (result.added <= 0) {
      final skipped = result.skipped.isEmpty ? 'those meals' : result.skipped.join(', ');
      final verb = result.skipped.length == 1 ? 'is' : 'are';
      return '$skipped $verb no longer available to reorder.$alt';
    }
    final extra = result.skipped.isEmpty ? '' : ' Skipped: ${result.skipped.join(', ')}.';
    return 'Added ${result.added} item${result.added == 1 ? '' : 's'} to your cart.$extra${result.skipped.isEmpty ? '' : alt}';
  }

  static Future<List<String>> _loadAlternatives({
    required Set<String> chefIds,
    required Set<String> excludeMealIds,
  }) async {
    try {
      final rows = await Supabase.instance.client
          .from('meals')
          .select('id, title, name, status, quantity, chef_id')
          .inFilter('chef_id', chefIds.toList())
          .eq('status', 'Available');
      return alternativeTitles(
        rows.map((row) => Map<String, dynamic>.from(row)).toList(),
        excludeMealIds: excludeMealIds,
      );
    } catch (_) {
      return const [];
    }
  }
}
