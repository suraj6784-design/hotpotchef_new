// lib/services/order_repository.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../models/order_status.dart';
import '../utils/network.dart';
import 'alert_service.dart';

Map<String, dynamic>? _functionData(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return null;
}

class OrderRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> updateOrderStatus({
    required String orderId,
    required String newStatus,
    String? driverId,
  }) async {
    try {
      final Map<String, dynamic> updateData = {
        'status': newStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (driverId != null) {
        updateData['driver_id'] = driverId;
      }

      final lowered = newStatus.toLowerCase();
      final completing = lowered == 'delivered' || lowered == 'completed';

      if (completing) {
        try {
          final done = await _supabase.rpc('complete_delivery_order', params: {'p_order_id': orderId});
          if (done == true) {
            AlertService.notifyOrder(orderId: orderId, type: 'UPDATE');
            unawaited(_releaseChefPayout(orderId));
            return;
          }
        } catch (_) {}
      }

      Future<void> write(Map<String, dynamic> payload) async {
        if (driverId != null) {
          await _supabase
              .from('orders')
              .update(payload)
              .eq('id', orderId)
              .filter('driver_id', 'is', null);
        } else {
          await _supabase.from('orders').update(payload).eq('id', orderId);
        }
      }

      await write(updateData);

      if (completing) {
        try {
          await write({'delivered_at': DateTime.now().toUtc().toIso8601String()});
        } catch (_) {}
        unawaited(_releaseChefPayout(orderId));
      }

      AlertService.notifyOrder(orderId: orderId, type: 'UPDATE');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to update order status to $newStatus');
      if (kDebugMode) debugPrint('Order update error: $e');
      throw Exception('Failed to update order status to $newStatus: $e');
    }
  }

  /// Atomic claim: only succeeds when `driver_id` is still null and the partner is online.
  Future<bool> acceptDelivery({required String orderId, required String driverId}) async {
    try {
      try {
        final viaRpc = await _supabase.rpc('accept_delivery_order', params: {'p_order_id': orderId});
        if (viaRpc == true) {
          AlertService.notifyOrder(orderId: orderId, type: 'UPDATE');
          return true;
        }
        if (viaRpc == false) return false;
      } catch (_) {
        // RPC not applied yet: fall back to the client-side race-safe update.
      }

      final response = await _supabase
          .from('orders')
          .update({
            'status': OrderStatus.driverAssigned,
            'driver_id': driverId,
            'delivery_partner_id': driverId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', orderId)
          .filter('driver_id', 'is', null)
          .filter('delivery_partner_id', 'is', null)
          .or('status.ilike.%ready%,status.ilike.%assigned%,status.ilike.%out for delivery%')
          .not('status', 'ilike', '%pending%')
          .select('id');

      final claimed = List<dynamic>.from(response).isNotEmpty;
      if (claimed) AlertService.notifyOrder(orderId: orderId, type: 'UPDATE');
      return claimed;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Driver order acceptance race condition loss');
      return false;
    }
  }

  Future<void> advanceDeliveryState({required String orderId, required bool isCurrentlyOutForDelivery}) async {
    final nextStatus = isCurrentlyOutForDelivery ? OrderStatus.delivered : OrderStatus.outForDelivery;
    await updateOrderStatus(orderId: orderId, newStatus: nextStatus);
  }

  Future<void> cancelOrder({
    required String orderId,
    String? chefId,
    String reason = 'Cancelled',
  }) async {
    try {
      final res = await _supabase.functions.invoke(
        'cancel-order',
        body: {
          'order_id': orderId,
          'reason': reason,
          if (chefId != null && chefId.isNotEmpty) 'chef_id': chefId,
        },
      ).withTimeout(NetworkTimeouts.payment);
      final data = _functionData(res.data);
      if (res.status != 200 || data == null || data['success'] != true) {
        throw Exception(data?['error'] ?? 'Cancellation rejected by server');
      }
    } on NetworkException catch (e) {
      throw Exception(e.message);
    } on FunctionException catch (e) {
      final details = _functionData(e.details);
      throw Exception(details?['error'] ?? e.reasonPhrase ?? 'Cancellation failed');
    }
  }

  Future<void> _releaseChefPayout(String orderId) async {
    try {
      await _supabase.functions.invoke(
        'release-chef-payout',
        body: {'order_id': orderId},
      ).withTimeout(NetworkTimeouts.payment);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef payout after delivery failed');
      if (kDebugMode) debugPrint('Chef payout error: $e');
    }
  }
}
