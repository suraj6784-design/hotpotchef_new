// lib/providers/cart_provider.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../models/cart_state.dart';
import '../models/cart_enums.dart';
import '../services/cart_service.dart';

void _logCartError(dynamic error, StackTrace stackTrace, String reason) {
  if (kDebugMode) {
    debugPrint('⚠️ Cart Error [$reason]: $error');
  }
  FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: reason);
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);

class CartNotifier extends Notifier<CartState> {
  final _supabase = Supabase.instance.client;
  final _cartService = CartService();

  Timer? _debounceTimer;
  RealtimeChannel? _stockChannel;
  bool _isInitialized = false;

  static const String _kLocalCartKey = 'local_cart_items_v2';

  @override
  CartState build() {
    ref.onDispose(() {
      _stockChannel?.unsubscribe();
      _debounceTimer?.cancel();
    });

    // Run async bootstrapper safely
    Future.microtask(() => _initializeCart());

    return const CartState(items: []);
  }

  // --- Initializer & Storage Sync ---

  Future<void> _initializeCart() async {
    await _loadLocalCart();
    await _loadRemoteCartAndReconcile();
    _isInitialized = true;
    _resubscribeStockWatcher();
  }

  Future<void> _loadLocalCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localData = prefs.getString(_kLocalCartKey);
      if (localData != null && localData.isNotEmpty) {
        final decoded = jsonDecode(localData) as List<dynamic>;
        final items = decoded
            .whereType<Map<String, dynamic>>()
            .map(CartItemModel.fromJson)
            .toList();
        state = state.copyWith(items: items);
      }
    } catch (e, st) {
      _logCartError(e, st, 'Failed reading local cart');
    }
  }

  Future<void> _loadRemoteCartAndReconcile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final remoteItems = await _cartService.fetchCart();
      if (remoteItems.isEmpty && state.items.isNotEmpty) {
        // User had offline items prior to sign-in: push local up
        await _cartService.saveCart(state.items);
      } else if (remoteItems.isNotEmpty) {
        // Production merge strategy: prefer remote items, resolve collisions
        state = state.copyWith(items: remoteItems);
        await _persistLocal();
      }
      await fetchUserCoins();
    } catch (e, st) {
      _logCartError(e, st, 'Failed syncing remote cart during bootstrap');
    }
  }

  Future<void> _persistLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = jsonEncode(state.items.map((i) => i.toJson()).toList());
      await prefs.setString(_kLocalCartKey, serialized);
    } catch (e, st) {
      _logCartError(e, st, 'Failed writing to SharedPreferences');
    }
  }

  void _scheduleRemoteSync() {
    _persistLocal();

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () async {
      final user = _supabase.auth.currentUser;
      if (user != null && _isInitialized) {
        try {
          await _cartService.saveCart(state.items);
        } catch (e, st) {
          _logCartError(e, st, 'Debounced remote cart sync failed');
        }
      }
    });
  }

  // --- Scoped Realtime Stock Synchronization ---

  void _resubscribeStockWatcher() {
    _stockChannel?.unsubscribe();

    if (state.items.isEmpty) return;

    // Isolate meal IDs currently active in cart to avoid global DB traffic
    final watchedMealIds = state.items.map((i) => i.mealId).toSet().toList();

    _stockChannel = _supabase
        .channel('cart_stock_sync_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'meals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.inFilter,
            column: 'id',
            value: watchedMealIds,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            final mealId = newRecord['id']?.toString() ?? '';
            final int stock = int.tryParse(newRecord['quantity']?.toString() ?? '0') ?? 0;
            final String status = newRecord['status']?.toString().toLowerCase() ?? 'available';

            final index = state.items.indexWhere((i) => i.mealId == mealId);
            if (index == -1) return;

            final currentItem = state.items[index];

            if (status == 'sold out' || status == 'paused' || stock <= 0) {
              removeItem(currentItem.id);
            } else if (currentItem.quantity > stock) {
              final diff = currentItem.quantity - stock;
              updateQuantity(currentItem.id, -diff);
            }
          },
        )
        .subscribe();
  }

  // --- Business Operations & Cart Actions ---

  bool addToCart(
    Map<String, dynamic> meal,
    int quantity, {
    List<CartItemAddOn> addOns = const [],
    bool clearIfVendorConflict = false,
  }) {
    final mealId = meal['id'].toString();
    final chefId = meal['chef_id'].toString();

    // Check multi-vendor restriction
    if (state.isNotEmpty && state.primaryChefId != chefId) {
      if (!clearIfVendorConflict) {
        return false;
      }
      state = state.copyWith(items: []);
    }

    final rawSlot = meal['time_slot']?.toString() ?? '';
    final smartSchedule = _calculateSmartDefaultSchedule(rawSlot);
    final rawServices = meal['service_type']?.toString() ?? 'Delivery (Platform)';
    final serviceType = ServiceType.fromString(rawServices.split(',').first.trim());
    final int availableStock = int.tryParse(meal['quantity']?.toString() ?? '99') ?? 99;

    // Prevent 0.00 checkout bug by strictly rejecting 0 values from discounted_price
    final double basePriceVal = (meal['price'] as num?)?.toDouble() ?? 0.0;
    final double? rawDiscount = (meal['discounted_price'] as num?)?.toDouble();
    final double? validDiscount = (rawDiscount != null && rawDiscount > 0) ? rawDiscount : null;

    // Deterministic item matching (considers add-on selection)
    final existingIndex = state.items.indexWhere(
      (i) => i.mealId == mealId && listEquals(i.selectedAddOns, addOns),
    );

    List<CartItemModel> updatedItems = List.from(state.items);

    if (existingIndex >= 0) {
      final existing = updatedItems[existingIndex];
      final targetQty = (existing.quantity + quantity).clamp(1, availableStock);
      updatedItems[existingIndex] = existing.copyWith(quantity: targetQty);
    } else {
      final scheduledDate = smartSchedule['date'] == 'Tomorrow'
          ? DateTime.now().add(const Duration(days: 1))
          : DateTime.now();

      final newItem = CartItemModel(
        id: '${mealId}_${DateTime.now().microsecondsSinceEpoch}',
        mealId: mealId,
        chefId: chefId,
        title: meal['name']?.toString() ?? 'Meal Item',
        basePrice: basePriceVal, // Safely assigned
        discountedPrice: validDiscount, // Safely assigned
        quantity: quantity.clamp(1, availableStock),
        scheduledDate: scheduledDate,
        timeSlot: smartSchedule['time'], // Initial time sync
        serviceType: serviceType,
        selectedAddOns: addOns,
        rawMealDetails: {
          ...meal,
          'exact_time': smartSchedule['time'],
          'max_quantity': availableStock,
        },
      );
      updatedItems.add(newItem);
    }

    state = state.copyWith(items: updatedItems);
    _resubscribeStockWatcher();
    _scheduleRemoteSync();
    return true;
  }

  void updateQuantity(String cartItemId, int delta) {
    final index = state.items.indexWhere((i) => i.id == cartItemId);
    if (index == -1) return;

    List<CartItemModel> updated = List.from(state.items);
    final item = updated[index];
    final int maxStock = int.tryParse(item.rawMealDetails['max_quantity']?.toString() ?? '99') ?? 99;

    final targetQty = item.quantity + delta;

    if (targetQty <= 0) {
      updated.removeAt(index);
    } else {
      updated[index] = item.copyWith(quantity: targetQty.clamp(1, maxStock));
    }

    state = state.copyWith(items: updated);
    if (updated.isEmpty) {
      _stockChannel?.unsubscribe();
    }
    _scheduleRemoteSync();
  }

  void removeItem(String cartItemId) {
    final updated = state.items.where((i) => i.id != cartItemId).toList();
    state = state.copyWith(items: updated);
    if (updated.isEmpty) {
      _stockChannel?.unsubscribe();
    }
    _scheduleRemoteSync();
  }

  Future<void> clearCart() async {
    _stockChannel?.unsubscribe();
    state = state.copyWith(items: [], applyCoins: false);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLocalCartKey);
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _cartService.saveCart([]);
      }
    } catch (e, st) {
      _logCartError(e, st, 'Failed executing clearCart');
    }
  }

  void setDeliveryFee(double fee) => state = state.copyWith(dynamicDeliveryFee: fee);
  void toggleCoins(bool apply) => state = state.copyWith(applyCoins: apply);

  Future<void> fetchUserCoins() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final data = await _supabase
          .from('users')
          .select('hotpot_coins')
          .eq('id', user.id)
          .maybeSingle();
      final coins = double.tryParse(data?['hotpot_coins']?.toString() ?? '0') ?? 0.0;
      state = state.copyWith(userCoinBalance: coins);
    } catch (e, st) {
      _logCartError(e, st, 'Failed fetching coin balance');
    }
  }

  Future<void> syncGuestCartToUser() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null || state.isEmpty) return;
      await _cartService.saveCart(state.items);
    } catch (e, st) {
      _logCartError(e, st, 'Failed to sync guest cart to user');
    }
  }

  void updateItemServiceType(String cartItemId, String serviceTypeStr) {
    final index = state.items.indexWhere((i) => i.id == cartItemId);
    if (index == -1) return;

    final updated = List<CartItemModel>.from(state.items);
    final item = updated[index];
    final serviceType = ServiceType.fromString(serviceTypeStr);

    updated[index] = item.copyWith(serviceType: serviceType);
    state = state.copyWith(items: updated);
    _scheduleRemoteSync();
  }

  void updateItemDate(String cartItemId, DateTime date) {
    final index = state.items.indexWhere((i) => i.id == cartItemId);
    if (index == -1) return;

    final updated = List<CartItemModel>.from(state.items);
    final item = updated[index];

    updated[index] = item.copyWith(scheduledDate: date);
    state = state.copyWith(items: updated);
    _scheduleRemoteSync();
  }

  // Propagates Time Slot strictly to both properties enforcing state regeneration
  void updateItemTimeSlot(String cartItemId, String timeSlot) {
    final index = state.items.indexWhere((i) => i.id == cartItemId);
    if (index == -1) return;

    final updated = List<CartItemModel>.from(state.items);
    final item = updated[index];

    final newRawDetails = Map<String, dynamic>.from(item.rawMealDetails);
    newRawDetails['exact_time'] = timeSlot;

    updated[index] = item.copyWith(
      timeSlot: timeSlot, 
      rawMealDetails: newRawDetails,
    );

    state = state.copyWith(items: updated);
    _scheduleRemoteSync();
  }

  Map<String, String> _calculateSmartDefaultSchedule(String chefScheduleStr) {
    final now = DateTime.now();
    final timeRegex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false);
    final matches = timeRegex.allMatches(chefScheduleStr).toList();

    if (matches.length >= 2) {
      int parseMins(RegExpMatch m) {
        int h = int.parse(m.group(1)!);
        if (m.group(3)!.toUpperCase() == 'PM' && h != 12) h += 12;
        if (m.group(3)!.toUpperCase() == 'AM' && h == 12) h = 0;
        return h * 60 + int.parse(m.group(2)!);
      }

      final startMins = parseMins(matches[0]);
      final endMins = parseMins(matches[1]);
      final nowMins = now.hour * 60 + now.minute;

      if (nowMins < startMins) {
        return {'date': 'Today', 'time': matches[0].group(0)!.toUpperCase()};
      } else if (nowMins >= startMins && nowMins <= (endMins - 40)) {
        final target = now.add(const Duration(minutes: 40));
        final h12 = target.hour == 0 ? 12 : (target.hour > 12 ? target.hour - 12 : target.hour);
        final ampm = target.hour >= 12 ? 'PM' : 'AM';
        return {'date': 'Today', 'time': '$h12:${target.minute.toString().padLeft(2, '0')} $ampm'};
      } else {
        return {'date': 'Tomorrow', 'time': matches[0].group(0)!.toUpperCase()};
      }
    }

    final fallback = now.add(const Duration(minutes: 40));
    final fh12 = fallback.hour == 0 ? 12 : (fallback.hour > 12 ? fallback.hour - 12 : fallback.hour);
    final fampm = fallback.hour >= 12 ? 'PM' : 'AM';
    return {'date': 'Today', 'time': '$fh12:${fallback.minute.toString().padLeft(2, '0')} $fampm'};
  }
}