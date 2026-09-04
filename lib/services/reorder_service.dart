import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_enums.dart';
import '../providers/cart_provider.dart';
import '../utils/helpers.dart';

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

  static Future<int> addOrderItemsToCart({
    required CartNotifier cart,
    required List<Map<String, dynamic>> items,
    bool clearIfVendorConflict = true,
  }) async {
    if (items.isEmpty) return 0;

    var added = 0;
    var allowClear = clearIfVendorConflict;

    for (final item in items) {
      final mealId = mealIdFromOrderItem(item);
      Map<String, dynamic> meal = {
        ...item,
        if (mealId != null) 'id': mealId,
        'title': item['title'] ?? item['name'] ?? 'Meal',
        'price': item['price'] ?? item['base_price'] ?? item['unit_price'] ?? 0,
        'chef_id': item['chef_id'],
        'quantity': item['max_quantity'] ?? item['available_quantity'] ?? 99,
      };

      if (mealId != null) {
        try {
          final live = await Supabase.instance.client
              .from('meals')
              .select()
              .eq('id', mealId)
              .maybeSingle();
          if (live != null) {
            meal = Map<String, dynamic>.from(live);
          }
        } catch (_) {}
      }

      final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
      final addOns = parseMealAddOns(
        item['selectedAddOns'] ?? item['selected_add_ons'] ?? item['add_ons'],
      );

      final ok = cart.addToCart(
        meal,
        qty.clamp(1, 20),
        addOns: addOns,
        clearIfVendorConflict: allowClear,
      );
      if (ok) {
        added += 1;
        allowClear = false;
      }
    }

    return added;
  }
}
