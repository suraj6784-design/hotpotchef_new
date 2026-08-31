// lib/services/order_repository.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class OrderRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Centralized method to update an order status with atomic validation and safety checks
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

      if (newStatus.toLowerCase() == 'delivered' || newStatus.toLowerCase() == 'completed') {
        updateData['delivered_at'] = DateTime.now().toUtc().toIso8601String();
      }

      // If assigning a driver, ensure atomic claim (driver_id must be currently null)
      if (driverId != null) {
        await _supabase
            .from('orders')
            .update(updateData)
            .eq('id', orderId)
            .filter('driver_id', 'is', null);
      } else {
        await _supabase
            .from('orders')
            .update(updateData)
            .eq('id', orderId);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to update order status to $newStatus');
      if (kDebugMode) debugPrint('Order update error: $e');
      throw Exception('Failed to update order status to $newStatus: $e');
    }
  }

  /// Specific helper for drivers accepting a job atomically
  Future<bool> acceptDelivery({required String orderId, required String driverId}) async {
    try {
      // Attempt atomic assignment
      await _supabase
          .from('orders')
          .update({
            'status': 'Driver Assigned',
            'driver_id': driverId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', orderId)
          .filter('driver_id', 'is', null);

      return true;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Driver order acceptance race condition loss');
      return false; // Order was already claimed by another driver
    }
  }

  /// Specific helper for advancing delivery states
  Future<void> advanceDeliveryState({required String orderId, required bool isCurrentlyOutForDelivery}) async {
    final nextStatus = isCurrentlyOutForDelivery ? 'Delivered' : 'Out for Delivery';
    await updateOrderStatus(
      orderId: orderId,
      newStatus: nextStatus,
    );
  }
}