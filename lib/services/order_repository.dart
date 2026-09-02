// lib/services/order_repository.dart

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
      AlertService.notifyOrder(orderId: orderId, type: 'UPDATE');
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
}
