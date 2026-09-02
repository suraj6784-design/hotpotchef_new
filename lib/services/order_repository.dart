// lib/services/order_repository.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../models/order_status.dart';

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
      if (lowered == 'delivered' || lowered == 'completed') {
        updateData['delivered_at'] = DateTime.now().toUtc().toIso8601String();
      }

      if (driverId != null) {
        await _supabase
            .from('orders')
            .update(updateData)
            .eq('id', orderId)
            .filter('driver_id', 'is', null);
      } else {
        await _supabase.from('orders').update(updateData).eq('id', orderId);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to update order status to $newStatus');
      if (kDebugMode) debugPrint('Order update error: $e');
      throw Exception('Failed to update order status to $newStatus: $e');
    }
  }

  /// Atomic claim: only succeeds when `driver_id` is still null.
  Future<bool> acceptDelivery({required String orderId, required String driverId}) async {
    try {
      final response = await _supabase
          .from('orders')
          .update({
            'status': OrderStatus.driverAssigned,
            'driver_id': driverId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', orderId)
          .filter('driver_id', 'is', null)
          .select('id');

      return List<dynamic>.from(response).isNotEmpty;
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
    if (chefId != null && chefId.isNotEmpty) {
      final res = await _supabase.rpc('cancel_and_restock_order', params: {
        'p_order_id': orderId,
        'p_chef_id': chefId,
        'p_reason': reason,
      });
      if (res is Map && res['success'] != true) {
        throw Exception(res['error'] ?? 'Cancellation rejected by server');
      }
      return;
    }

    await _supabase.from('orders').update({
      'status': OrderStatus.cancelled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }
}
