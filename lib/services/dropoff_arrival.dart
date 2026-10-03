import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/delivery_pin.dart';
import '../utils/helpers.dart';

/// Records that the assigned partner is at the diner's dropoff.
class DropoffArrival {
  DropoffArrival._();

  static Future<bool> markIfReached({
    required String orderId,
    required double driverLat,
    required double driverLng,
    required double? dropoffLat,
    required double? dropoffLng,
    required String? status,
    String? arrivedAt,
    SupabaseClient? client,
  }) async {
    final id = orderId.trim();
    if (id.isEmpty) return false;
    if ((arrivedAt ?? '').trim().isNotEmpty) return true;
    if (!driverRunIsOutForDelivery(status)) return false;
    if (!driverHasReachedDropoff(
      driverLat: driverLat,
      driverLng: driverLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
    )) {
      return false;
    }
    try {
      final done = await (client ?? Supabase.instance.client).rpc(
        'mark_driver_at_dropoff',
        params: {'p_order_id': id, 'p_lat': driverLat, 'p_lng': driverLng},
      );
      return done == true;
    } catch (_) {
      return false;
    }
  }
}
