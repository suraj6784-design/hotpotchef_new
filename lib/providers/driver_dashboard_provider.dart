// lib/providers/driver_dashboard_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../models/driver_delivery_model.dart';

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

      // 1. Available Pool (Unassigned & Ready for Pickup)
      final availableFuture = _supabase
          .from('orders')
          .select('*, chefs(business_name, pickup_address)')
          .isFilter('driver_id', null)
          .ilike('status', '%ready%')
          .order('created_at', ascending: false)
          .limit(25);

      // 2. Driver Active Deliveries (In-Progress)
      final activeFuture = _supabase
          .from('orders')
          .select('*, chefs(business_name, pickup_address)')
          .eq('driver_id', user.id)
          .not('status', 'ilike', '%delivered%')
          .not('status', 'ilike', '%cancelled%')
          .order('created_at', ascending: false);

      // 3. Paginated Recent Completed Deliveries
      final completedRecentFuture = _supabase
          .from('orders')
          .select('*, chefs(business_name, pickup_address)')
          .eq('driver_id', user.id)
          .ilike('status', '%delivered%')
          .order('created_at', ascending: false)
          .limit(15);

      // 4. Server-Side Aggregate Count for Performance
      final completedCountFuture = _supabase
          .from('orders')
          .count(CountOption.exact)
          .eq('driver_id', user.id)
          .ilike('status', '%delivered%');

      // 5. Driver Total Earnings (Fetched via RPC or Driver Profile aggregation)
      final earningsFuture = _supabase
          .from('driver_profiles')
          .select('wallet_balance, total_lifetime_earnings')
          .eq('user_id', user.id)
          .maybeSingle();

      final results = await Future.wait([
        availableFuture,
        activeFuture,
        completedRecentFuture,
        completedCountFuture,
        earningsFuture,
      ].cast<Future<dynamic>>());

      final availableList = (results[0] as List)
          .map((e) => DriverDeliveryModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final activeList = (results[1] as List)
          .map((e) => DriverDeliveryModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final recentList = (results[2] as List)
          .map((e) => DriverDeliveryModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final totalCompletedCount = (results[3] as PostgrestResponse).count ?? 0;
      
      final profileData = results[4] as Map<String, dynamic>?;
      final earnings = (profileData?['wallet_balance'] as num?)?.toDouble() ??
          (profileData?['total_lifetime_earnings'] as num?)?.toDouble() ??
          (totalCompletedCount * 40.0); // Safe fallback

      state = state.copyWith(
        isLoading: false,
        totalEarnings: earnings,
        completedCount: totalCompletedCount,
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
      // ATOMIC CONCURRENCY GUARD:
      // Only updates if driver_id is STILL null at execution time.
      final response = await _supabase
          .from('orders')
          .update({
            'driver_id': user.id,
            'status': DeliveryStatus.accepted.toDbValue(),
            'accepted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .isFilter('driver_id', null)
          .select();

      final updatedRows = List<Map<String, dynamic>>.from(response);

      if (updatedRows.isEmpty) {
        // Another driver claimed the order a split-second earlier
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
      await _supabase.from('orders').update({
        'status': nextStatus.toDbValue(),
        if (nextStatus == DeliveryStatus.delivered) 'delivered_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId).eq('driver_id', user.id);

      await loadDashboardData(isSilentRefresh: true);
      return true;
    } catch (e, st) {
      _logDriverError(e, st, 'Failed status update for order: $orderId');
      return false;
    }
  }
}