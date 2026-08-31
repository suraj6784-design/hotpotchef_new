// lib/services/cart_service.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../models/cart_state.dart';

class CartService {
  final _supabase = Supabase.instance.client;

  /// Fetches the user's cart items from the remote 'carts' table securely
  Future<List<CartItemModel>> fetchCart() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final response = await _supabase
          .from('carts')
          .select('items')
          .eq('user_id', user.id)
          .maybeSingle();

      if (response != null && response['items'] is List) {
        final rawList = response['items'] as List;
        return rawList
            .map((e) => CartItemModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch remote cart');
      if (kDebugMode) debugPrint('Error fetching cart: $e');
    }
    return [];
  }

  /// Saves or updates the user's cart items securely to the remote 'carts' table
  Future<void> saveCart(List<CartItemModel> items) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final jsonList = items.map((i) => i.toJson()).toList();

      await _supabase.from('carts').upsert(
        {
          'user_id': user.id,
          'items': jsonList,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to save remote cart');
      if (kDebugMode) debugPrint('Error saving cart: $e');
    }
  }

  /// Clears the remote cart table for the authenticated user
  Future<void> clearRemoteCart() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('carts').delete().eq('user_id', user.id);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to clear remote cart');
      if (kDebugMode) debugPrint('Error clearing cart: $e');
    }
  }
}