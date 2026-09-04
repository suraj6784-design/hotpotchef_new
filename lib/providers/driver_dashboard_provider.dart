// lib/providers/driver_dashboard_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../models/driver_delivery_model.dart';
import '../models/cart_enums.dart';
import '../services/order_lifecycle.dart';
import '../utils/helpers.dart';

void _logDriverError(dynamic error, StackTrace stackTrace, String reason) {
  if (kDebugMode) {
    debugPrint('⚠️ Driver Dashboard Error [$reason]: $error');
  }
  FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: reason);
}

final driverDashboardProvider =
    NotifierProvider<DriverDashboardNotifier, DriverDashboardState>(DriverDashboardNotifier.new);

class DriverDashboardNotifier extends Notifier<DriverDashboardState> {
  final _supabase = Supabase.instance.client;
  final _lifecycle = OrderLifecycle();
  RealtimeChannel? _dispatchChannel;

  @override
  DriverDashboardState build() {
    ref.onDispose(() {
      _dispatchChannel?.unsubscribe();
    });

    Future.microtask(() {
      loadDashboardData();
      _initLiveDispatchFeed();
    });

    return const DriverDashboardState();
  }

  // --- Realtime WebSocket Dispatch Channel ---

  void _initLiveDispatchFeed() {
    _dispatchChannel?.unsubscribe();

    // Listen to orders table for newly ready deliveries or status transitions
    _dispatchChannel = _supabase
        .channel('public:orders:driver_dispatch')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            // Live refresh of pending pools without locking UI
            loadDashboardData(isSilentRefresh: true);
          },
        )
        .subscribe();
  }

  // --- Data Loading & Aggregation ---

  Future<void> loadDashboardData({bool isSilentRefresh = false}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        state = state.copyWith(isLoading: false, errorMessage: 'Driver not authenticated');
        return;
      }

      if (!isSilentRefresh) {
        state = state.copyWith(isLoading: true, errorMessage: null);
      }

      final mine = 'driver_id.eq.${user.id},delivery_partner_id.eq.${user.id}';

      // 1. Unassigned partner jobs (pending through ready, plus orphaned out-for-delivery)
      final availableFuture = _supabase
          .from('orders')
          .select()
          .isFilter('driver_id', null)
          .isFilter('delivery_partner_id', null)
          .not('status', 'ilike', '%delivered%')
          .not('status', 'ilike', '%cancelled%')
          .not('status', 'ilike', '%rejected%')
          .not('status', 'ilike', '%completed%')
          .order('created_at', ascending: false)
          .limit(40);

      // 2. Driver Active Deliveries (In-Progress)
      final activeFuture = _supabase
          .from('orders')
          .select()
          .or(mine)
          .not('status', 'ilike', '%delivered%')
          .not('status', 'ilike', '%cancelled%')
          .order('created_at', ascending: false);

      // 3. Paginated Recent Completed Deliveries
      final completedRecentFuture = _supabase
          .from('orders')
          .select()
          .or(mine)
          .ilike('status', '%delivered%')
          .order('created_at', ascending: false)
          .limit(100);

      // 4. Driver Total Earnings (best-effort; missing profile columns must not blank Home)
      final earningsFuture = _supabase
          .from('driver_profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      final results = await Future.wait([
        availableFuture,
        activeFuture,
        completedRecentFuture,
        earningsFuture,
      ].cast<Future<dynamic>>());

      final availableList = (results[0] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) =>
              ServiceType.fromString(
                e['order_type']?.toString() ?? e['service_type']?.toString(),
              ).usesDeliveryPartner &&
              OrderLifecycle.isOpenDriverJob(e['status']?.toString()))
          .map(DriverDeliveryModel.fromJson)
          .toList();

      final activeList = (results[1] as List)
          .map((e) => DriverDeliveryModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final completedList = (results[2] as List)
          .map((e) => DriverDeliveryModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final recentList = completedList.take(15).toList();

      final profileData = results[3] is Map
          ? Map<String, dynamic>.from(results[3] as Map)
          : null;
      final earnings = fleetEarningsFrom(
        wallet: parseMoney(profileData?['wallet_balance']),
        lifetime: parseMoney(profileData?['total_lifetime_earnings']),
        deliveryPayouts: completedList.map((delivery) => delivery.payout),
      );

      state = state.copyWith(
        isLoading: false,
        totalEarnings: earnings,
        completedCount: completedList.length,
        availableDeliveries: availableList,
        activeDeliveries: activeList,
        recentDeliveries: recentList,
      );
    } catch (e, st) {
      _logDriverError(e, st, 'Failed loading driver dashboard metrics');
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to synchronize orders.');
    }
  }

  // --- Atomic Order Acceptance ---

  /// Attempts to claim an available delivery order.
  /// Returns `true` if secured successfully, `false` if snatched by another driver.
  Future<bool> acceptOrder(String orderId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final success = await _lifecycle.acceptDelivery(orderId: orderId, driverId: user.id);
      if (!success) {
        state = state.copyWith(
          errorMessage: 'Order was already accepted by another partner.',
        );
        await loadDashboardData(isSilentRefresh: true);
        return false;
      }

      await loadDashboardData(isSilentRefresh: true);
      return true;
    } catch (e, st) {
      _logDriverError(e, st, 'Atomic acceptOrder failed for ID: $orderId');
      state = state.copyWith(errorMessage: 'Network error while accepting order.');
      return false;
    }
  }

  // --- Status Transition Handling ---

  Future<bool> updateDeliveryStatus(String orderId, DeliveryStatus nextStatus) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      await _lifecycle.advanceDriver(
        orderId: orderId,
        currentStatus: nextStatus == DeliveryStatus.delivered
            ? OrderStatus.outForDelivery
            : OrderStatus.driverAssigned,
      );

      await loadDashboardData(isSilentRefresh: true);
      return true;
    } catch (e, st) {
      _logDriverError(e, st, 'Failed status update for order: $orderId');
      state = state.copyWith(errorMessage: 'Could not update this run. Try again.');
      return false;
    }
  }
}