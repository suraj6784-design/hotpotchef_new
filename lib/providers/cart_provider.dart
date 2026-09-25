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
import '../services/app_analytics.dart';
import '../utils/helpers.dart';
import '../utils/delivery_fee.dart';

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

  List<CartItemModel> _applySharedSlotToItems(List<CartItemModel> items, String? slot) {
    final cleaned = slot?.trim() ?? '';
    if (cleaned.isEmpty || items.isEmpty) return items;
    return [for (final item in items) item.copyWith(timeSlot: cleaned)];
  }

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
      final room = state.sharedRoomCode;
      final inSharedRoom = room != null && room.isNotEmpty;
      // While in a group cart, only sync the shared room — avoid overwriting the
      // host/guest personal remote cart with the group basket.
      if (user != null && _isInitialized && !inSharedRoom) {
        try {
          await _cartService.saveCart(state.items);
        } catch (e, st) {
          _logCartError(e, st, 'Debounced remote cart sync failed');
        }
      }
      if (inSharedRoom && !_applyingSharedCart) {
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
    final slot = timeSlot?.trim();
    var nextItems = state.items;
    if (slot != null && slot.isNotEmpty && nextItems.isNotEmpty) {
      nextItems = [
        for (final item in nextItems) item.copyWith(timeSlot: slot),
      ];
    }
    state = state.copyWith(
      items: nextItems,
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
      state = state.copyWith(
        items: _applySharedSlotToItems(items, state.sharedTimeSlot),
        sharedRoomCode: code,
      );
      _persistLocal();
      _applyingSharedCart = false;
    }, onError: (e, st) {
      _logCartError(e, st, 'Shared cart stream failed');
    });
  }

  /// Copies the room's plates into this cart and keeps later adds in sync.
  Future<SharedCartJoinResult> joinSharedRoom(String rawCode) async {
    final code = parseGroupRoomCode(rawCode);
    if (code == null) {
      throw SharedCartException('Enter a room code like GRP-AB12CD, or paste the group link.');
    }
    if (_supabase.auth.currentUser == null) {
      throw SharedCartException('Sign in to join this group.');
    }
    final room = await _sharedCartService.fetchSharedCartRoom(code);
    var added = 0;
    final skipped = <String>[];
    var allowClear = true;
    for (final item in room.items) {
      final meal = item.toMealMap();
      if ((meal['id']?.toString() ?? '').isEmpty) {
        skipped.add(item.title.isEmpty ? 'a dish' : item.title);
        continue;
      }
      final ok = addToCart(
        meal,
        item.quantity,
        addOns: item.selectedAddOns,
        clearIfVendorConflict: allowClear,
        timeSlot: (room.timeSlot ?? '').trim().isEmpty ? null : room.timeSlot,
      );
      if (ok) {
        added += 1;
        allowClear = false;
      } else {
        skipped.add(item.title.isEmpty ? 'a dish' : item.title);
      }
    }
    await attachSharedRoom(
      code,
      placeKind: room.placeKind,
      placeLabel: room.placeLabel,
      dropoffNote: room.dropoffNote,
      timeSlot: room.timeSlot,
      hostId: room.hostId,
    );
    return SharedCartJoinResult(
      roomCode: code,
      placeKind: room.placeKind,
      added: added,
      skipped: skipped,
    );
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
              final remaining = state.items.where((i) => i.id != currentItem.id).toList();
              _commitItems(
                remaining,
                stockNotice: '${currentItem.title} sold out and was removed from your cart.',
              );
              if (remaining.isEmpty) {
                _stockChannel?.unsubscribe();
              }
              _scheduleRemoteSync();
            } else {
              final livePrice = double.tryParse(newRecord['price']?.toString() ?? '');
              final liveDiscount = double.tryParse(newRecord['discounted_price']?.toString() ?? '');
              final merged = Map<String, dynamic>.from(currentItem.rawMealDetails)..addAll({
                ...newRecord,
                'max_quantity': stock,
              });
              final updated = List<CartItemModel>.from(state.items);
              updated[index] = currentItem.copyWith(
                basePrice: livePrice != null && livePrice > 0 ? livePrice : currentItem.basePrice,
                discountedPrice: (liveDiscount != null && liveDiscount > 0) ? liveDiscount : currentItem.discountedPrice,
                quantity: currentItem.quantity > stock ? stock : currentItem.quantity,
                selectedAddOns: pricedAddOnsFromCatalog(
                  catalog: newRecord['add_ons'] ?? newRecord['addons'],
                  selected: currentItem.selectedAddOns,
                ),
                rawMealDetails: merged,
              );
              _commitItems(updated);
              _scheduleRemoteSync();
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
    DateTime? scheduledDate,
    String? timeSlot,
    String? specialInstructions,
    ServiceType? serviceType,
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
    final resolvedService = serviceType ??
        ServiceType.fromString(
          (meal['service_type']?.toString() ?? 'Delivery Partner').split(',').first.trim(),
        );
    final int availableStock = int.tryParse(meal['quantity']?.toString() ?? '99') ?? 99;
    final pricedAddOns = pricedAddOnsFromCatalog(
      catalog: meal['add_ons'] ?? meal['addons'],
      selected: addOns,
    );

    final double basePriceVal = double.tryParse(meal['price']?.toString() ?? '') ?? 0.0;
    final double? rawDiscount = double.tryParse(meal['discounted_price']?.toString() ?? '');
    final double? validDiscount = (rawDiscount != null && rawDiscount > 0) ? rawDiscount : null;

    final resolvedSlot = (timeSlot ?? '').trim().isNotEmpty
        ? timeSlot!.trim()
        : ((smartSchedule['time'] ?? '').trim().isNotEmpty
            ? smartSchedule['time']!.trim()
            : (preferredChefSlotClock(rawSlot) ?? rawSlot));
    final resolvedDate = scheduledDate ?? chefSlotDefaultDate(smartSchedule);
    final note = specialInstructions?.trim();

    final existingIndex = state.items.indexWhere(
      (i) => i.mealId == mealId && listEquals(i.selectedAddOns, pricedAddOns),
    );

    List<CartItemModel> updatedItems = List.from(state.items);

    if (existingIndex >= 0) {
      final existing = updatedItems[existingIndex];
      final targetQty = (existing.quantity + quantity).clamp(1, availableStock);
      final raw = Map<String, dynamic>.from(existing.rawMealDetails);
      raw['exact_time'] = resolvedSlot;
      updatedItems[existingIndex] = existing.copyWith(
        quantity: targetQty,
        scheduledDate: resolvedDate,
        timeSlot: resolvedSlot,
        serviceType: resolvedService,
        specialInstructions: (note == null || note.isEmpty) ? existing.specialInstructions : note,
        rawMealDetails: raw,
      );
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
        serviceType: resolvedService,
        selectedAddOns: pricedAddOns,
        specialInstructions: (note == null || note.isEmpty) ? null : note,
        rawMealDetails: {
          ...meal,
          'exact_time': resolvedSlot,
          'max_quantity': availableStock,
        },
      );
      updatedItems.add(newItem);
    }

    state = state.copyWith(
      items: updatedItems,
      packagingFee: _packagingFor(updatedItems),
    );
    _resubscribeStockWatcher();
    _scheduleRemoteSync();
    unawaited(AppAnalytics.logAddToCart(mealId: mealId, chefId: chefId, quantity: quantity));
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

    _commitItems(updated);
    if (updated.isEmpty) {
      _stockChannel?.unsubscribe();
    }
    _scheduleRemoteSync();
  }

  void removeItem(String cartItemId) {
    final updated = state.items.where((i) => i.id != cartItemId).toList();
    _commitItems(updated);
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
    state = state.copyWith(items: [], applyCoins: false, packagingFee: kDefaultPackagingFee);

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
  void clearStockNotice() {
    if (state.stockNotice != null) {
      state = state.copyWith(clearStockNotice: true);
    }
  }

  double _packagingFor(List<CartItemModel> items, {String? loyaltyTier}) {
    return packagingFeeForCartItems(
      items.map((item) => item.toCheckoutPayload()),
      loyaltyTier: loyaltyTier ?? state.loyaltyTier,
      foodTotal: items.fold<double>(0.0, (sum, item) => sum + state.getEffectiveItemTotal(item)),
    );
  }

  void _commitItems(List<CartItemModel> items, {String? stockNotice}) {
    state = state.copyWith(
      items: items,
      packagingFee: _packagingFor(items),
      stockNotice: stockNotice,
    );
  }

  Future<void> refreshDeliveryQuote() async {
    if (!state.hasDelivery) {
      if (state.dynamicDeliveryFee != 0) {
        state = state.copyWith(dynamicDeliveryFee: 0);
      }
      return;
    }
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final addresses = await _supabase.from('user_addresses').select().eq('user_id', user.id);
      final list = List<Map<String, dynamic>>.from(addresses as List);
      Map<String, dynamic>? chosen;
      for (final row in list) {
        if (row['is_default'] == true) {
          chosen = row;
          break;
        }
      }
      chosen ??= list.isNotEmpty ? list.first : null;
      chosen ??= await _supabase
          .from('users')
          .select('lat, lng, latitude, longitude')
          .eq('id', user.id)
          .maybeSingle();

      final dropLat = addressCoordinate(chosen, latitude: true);
      final dropLng = addressCoordinate(chosen, latitude: false);
      if (dropLat == null || dropLng == null) {
        state = state.copyWith(dynamicDeliveryFee: 0);
        return;
      }

      final chefIds = state.vendorIds.where((id) => id.isNotEmpty).toList();
      if (chefIds.isEmpty) {
        state = state.copyWith(
          dynamicDeliveryFee: customerDeliveryFee(
            distanceQuote: quoteCheckoutDeliveryFee(cartItems: state.items.map((i) => i.toCheckoutPayload())),
            foodTotal: state.foodTotal,
            hasDelivery: true,
            membershipWaivesDelivery: state.membershipWaivesDelivery,
          ),
        );
        return;
      }
      final chefsData = await _supabase.from('users').select('id, lat, lng').inFilter('id', chefIds);
      final chefLocations = <String, ({double? lat, double? lng})>{
        for (final c in chefsData)
          c['id'].toString(): (
            lat: double.tryParse(c['lat']?.toString() ?? ''),
            lng: double.tryParse(c['lng']?.toString() ?? ''),
          ),
      };
      final fee = customerDeliveryFee(
        distanceQuote: quoteCheckoutDeliveryFee(
          cartItems: state.items.map((i) => i.toCheckoutPayload()),
          dropLat: dropLat,
          dropLng: dropLng,
          chefLocations: chefLocations,
        ),
        foodTotal: state.foodTotal,
        hasDelivery: true,
        membershipWaivesDelivery: state.membershipWaivesDelivery,
      );
      state = state.copyWith(dynamicDeliveryFee: fee);
    } catch (e, st) {
      _logCartError(e, st, 'Failed quoting cart delivery fee');
    }
  }

  void setUserCoinBalance(double coins) {
    final next = coins < 0 ? 0.0 : coins;
    if (state.userCoinBalance == next) return;
    state = state.copyWith(userCoinBalance: next);
  }

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
      String? tier;
      var member = false;
      try {
        final gam = await _supabase
            .from('user_gamification')
            .select('loyalty_tier')
            .eq('user_id', user.id)
            .maybeSingle();
        tier = gam?['loyalty_tier']?.toString();
      } catch (_) {}
      try {
        final waived = await _supabase.rpc('diner_membership_waives_delivery');
        member = waived == true;
      } catch (_) {}
      state = state.copyWith(
        userCoinBalance: coins,
        loyaltyTier: tier,
        membershipWaivesDelivery: member,
        packagingFee: _packagingFor(state.items, loyaltyTier: tier),
        applyCoins: state.applyCoins && state.coinsAcceptedByVendors,
      );
      await refreshDeliveryQuote();
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

  void updateItemAddOns(
    String cartItemId,
    List<CartItemAddOn> addOns, {
    dynamic catalog,
  }) {
    final index = state.items.indexWhere((i) => i.id == cartItemId);
    if (index == -1) return;

    final updated = List<CartItemModel>.from(state.items);
    final item = updated[index];
    final nextRaw = Map<String, dynamic>.from(item.rawMealDetails);
    if (catalog != null) {
      nextRaw['add_ons'] = catalog;
    }
    final priced = pricedAddOnsFromCatalog(
      catalog: nextRaw['add_ons'] ?? nextRaw['addons'],
      selected: addOns,
    );
    updated[index] = CartItemModel(
      id: item.id,
      mealId: item.mealId,
      chefId: item.chefId,
      title: item.title,
      basePrice: item.basePrice,
      discountedPrice: item.discountedPrice,
      quantity: item.quantity,
      scheduledDate: item.scheduledDate,
      serviceType: item.serviceType,
      timeSlot: item.timeSlot,
      selectedAddOns: priced,
      specialInstructions: item.specialInstructions,
      rawMealDetails: Map.unmodifiable(nextRaw),
    );
    _commitItems(updated);
    _scheduleRemoteSync();
  }

  void updateItemServiceType(String cartItemId, String serviceTypeStr) {
    final index = state.items.indexWhere((i) => i.id == cartItemId);
    if (index == -1) return;

    final updated = List<CartItemModel>.from(state.items);
    final item = updated[index];
    final serviceType = ServiceType.fromString(serviceTypeStr);

    updated[index] = item.copyWith(serviceType: serviceType);
    _commitItems(updated);
    _scheduleRemoteSync();
  }

  void updateItemDate(String cartItemId, DateTime date) {
    final index = state.items.indexWhere((i) => i.id == cartItemId);
    if (index == -1) return;

    final updated = List<CartItemModel>.from(state.items);
    final item = updated[index];

    updated[index] = item.copyWith(scheduledDate: date);
    _commitItems(updated);
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

    _commitItems(updated);
    _scheduleRemoteSync();
  }
}