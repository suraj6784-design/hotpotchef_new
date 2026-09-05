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
import '../services/shared_cart_service.dart';
import '../utils/helpers.dart';

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
  final _sharedCartService = SharedCartService();

  Timer? _debounceTimer;
  RealtimeChannel? _stockChannel;
  StreamSubscription<List<CartItemModel>>? _sharedCartSub;
  bool _isInitialized = false;
  bool _applyingSharedCart = false;

  static const String _kLocalCartKey = 'local_cart_items_v2';

  @override
  CartState build() {
    ref.onDispose(() {
      _stockChannel?.unsubscribe();
      _sharedCartSub?.cancel();
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
      final room = state.sharedRoomCode;
      if (room != null && room.isNotEmpty && !_applyingSharedCart) {
        try {
          await _sharedCartService.updateSharedCart(room, state.items);
        } catch (e, st) {
          _logCartError(e, st, 'Debounced shared cart sync failed');
        }
      }
    });
  }

  Future<void> attachSharedRoom(
    String roomCode, {
    String? placeKind,
    String? placeLabel,
    String? dropoffNote,
    String? timeSlot,
    String? hostId,
  }) async {
    final code = roomCode.trim().toUpperCase();
    if (code.isEmpty) return;
    final resolvedHost = hostId ?? await _sharedCartService.sharedCartHostId(code);
    state = state.copyWith(
      sharedRoomCode: code,
      sharedHostId: resolvedHost,
      sharedPlaceKind: placeKind,
      sharedPlaceLabel: placeLabel,
      sharedDropoffNote: dropoffNote,
      sharedTimeSlot: timeSlot,
    );
    _sharedCartSub?.cancel();
    _sharedCartSub = _sharedCartService.streamSharedCart(code).listen((items) {
      if (_applyingSharedCart) return;
      _applyingSharedCart = true;
      final roomClosed = items.isEmpty && state.isNotEmpty && state.sharedRoomCode == code;
      if (roomClosed) {
        detachSharedRoom();
        _applyingSharedCart = false;
        return;
      }
      state = state.copyWith(items: items, sharedRoomCode: code);
      _persistLocal();
      _applyingSharedCart = false;
    }, onError: (e, st) {
      _logCartError(e, st, 'Shared cart stream failed');
    });
  }

  void detachSharedRoom() {
    _sharedCartSub?.cancel();
    _sharedCartSub = null;
    state = state.copyWith(clearSharedRoom: true);
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
    final smartSchedule = chefSlotDefaultSchedule(rawSlot);
    final serviceType = ServiceType.fromString(
      (meal['service_type']?.toString() ?? 'Delivery Partner').split(',').first.trim(),
    );
    final int availableStock = int.tryParse(meal['quantity']?.toString() ?? '99') ?? 99;

    final double basePriceVal = double.tryParse(meal['price']?.toString() ?? '') ?? 0.0;
    final double? rawDiscount = double.tryParse(meal['discounted_price']?.toString() ?? '');
    final double? validDiscount = (rawDiscount != null && rawDiscount > 0) ? rawDiscount : null;

    final resolvedSlot = (smartSchedule['time'] ?? '').trim().isNotEmpty
        ? smartSchedule['time']!.trim()
        : (preferredChefSlotClock(rawSlot) ?? rawSlot);
    final resolvedDate = smartSchedule['date'] == 'Tomorrow'
        ? tomorrowCalendarDay()
        : calendarDay(DateTime.now());

    final existingIndex = state.items.indexWhere(
      (i) => i.mealId == mealId && listEquals(i.selectedAddOns, addOns),
    );

    List<CartItemModel> updatedItems = List.from(state.items);

    if (existingIndex >= 0) {
      final existing = updatedItems[existingIndex];
      final targetQty = (existing.quantity + quantity).clamp(1, availableStock);
      updatedItems[existingIndex] = existing.copyWith(quantity: targetQty);
    } else {
      final newItem = CartItemModel(
        id: '${mealId}_${DateTime.now().microsecondsSinceEpoch}',
        mealId: mealId,
        chefId: chefId,
        title: meal['title']?.toString() ?? meal['name']?.toString() ?? 'Meal Item',
        basePrice: basePriceVal,
        discountedPrice: validDiscount,
        quantity: quantity.clamp(1, availableStock),
        scheduledDate: resolvedDate,
        timeSlot: resolvedSlot,
        serviceType: serviceType,
        selectedAddOns: addOns,
        rawMealDetails: {
          ...meal,
          'exact_time': resolvedSlot,
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
    final room = state.sharedRoomCode;
    _stockChannel?.unsubscribe();
    if (room != null && room.isNotEmpty) {
      try {
        await _sharedCartService.markSharedCartOrdered(room);
      } catch (e, st) {
        _logCartError(e, st, 'Failed closing shared cart room');
      }
    }
    detachSharedRoom();
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
  void toggleCoins(bool apply) =>
      state = state.copyWith(applyCoins: apply && state.coinsAcceptedByVendors);

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
      var packaging = state.packagingFee;
      try {
        final gam = await _supabase
            .from('user_gamification')
            .select('loyalty_tier')
            .eq('user_id', user.id)
            .maybeSingle();
        packaging = packagingFeeForLoyaltyTier(gam?['loyalty_tier']?.toString());
      } catch (_) {}
      state = state.copyWith(
        userCoinBalance: coins,
        packagingFee: packaging,
        applyCoins: state.applyCoins && state.coinsAcceptedByVendors,
      );
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
}