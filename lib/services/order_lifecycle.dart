import 'dart:async';

import '../models/cart_enums.dart';
import '../models/order_status.dart';
import '../utils/helpers.dart';
import 'app_analytics.dart';
import 'order_repository.dart';

export '../models/order_status.dart';

/// Chef kitchen → Ready for Pickup → dispatch; driver / customer transitions.
class OrderLifecycle {
  OrderLifecycle({OrderRepository? repository}) : _repo = repository ?? OrderRepository();

  final OrderRepository _repo;

  static String normalize(String? status) => status?.trim().toLowerCase() ?? '';

  static bool isPendingKitchen(String? status) {
    final s = normalize(status);
    return s.contains('pending') || s == 'placed' || s == 'new';
  }

  static bool isKitchenActive(String? status) {
    final s = normalize(status);
    return isPendingKitchen(status) || s == 'confirmed' || s == 'preparing';
  }

  /// Unassigned partner jobs drivers may claim: kitchen-ready or orphaned in transit.
  static bool isOpenDriverJob(String? status) {
    if (isKitchenActive(status)) return false;
    return isDispatchQueue(status);
  }

  static bool canDriverStartRun(String? status) {
    final s = normalize(status);
    return s.contains('ready') || s.contains('assigned') || s.contains('accept');
  }

  /// After accept: partner is going to the chef kitchen.
  static bool canDriverMarkHeadingToPickup(String? status) {
    final s = normalize(status);
    if (isHeadingToPickup(status) || canDriverCompleteRun(status)) return false;
    return canDriverStartRun(status);
  }

  static bool isHeadingToPickup(String? status) {
    final s = normalize(status);
    return s.contains('heading') ||
        s.contains('en route to pickup') ||
        s.contains('on the way to pickup');
  }

  static bool canDriverConfirmPickup(String? status) => isHeadingToPickup(status);

  static bool canDriverCompleteRun(String? status) {
    final s = normalize(status);
    return s.contains('out') && !s.contains('timeout');
  }

  static String driverHubBadge(String? status) {
    if (canDriverMarkHeadingToPickup(status) || isHeadingToPickup(status)) {
      return 'On the way to pickup';
    }
    final raw = status?.trim() ?? '';
    return raw.isEmpty ? 'Delivery' : raw;
  }

  static String driverHubActionLabel(String? status) {
    if (canDriverCompleteRun(status)) return 'Mark Delivered';
    if (canDriverConfirmPickup(status)) return 'Picked up';
    if (canDriverMarkHeadingToPickup(status)) return 'On the way to pickup';
    return '';
  }

  /// Orders the kitchen already accepted and still owes the customer.
  static bool isUnfulfilledKitchenWork(String? status) {
    return isKitchenActive(status) || isDispatchQueue(status);
  }

  static bool chefHasUnfulfilledOrders(Iterable<dynamic> orders) {
    return orders.whereType<Map>().any((order) {
      return isUnfulfilledKitchenWork(order['status']?.toString());
    });
  }

  static bool isDispatchQueue(String? status) {
    final s = normalize(status);
    return s.contains('ready') ||
        s.contains('assigned') ||
        s.contains('heading') ||
        s.contains('out for delivery') ||
        s.contains('out_for_delivery');
  }

  /// Handed to the diner — not "out for delivery".
  static bool isFulfilled(String? status) {
    final s = normalize(status);
    if (s.contains('out for delivery') || s.contains('out_for_delivery')) return false;
    return s.contains('delivered') || s.contains('completed');
  }

  /// Live map after the kitchen marks Ready for Pickup (and while the partner is en route).
  static bool isTrackable(String? status) {
    if (isFulfilled(status)) return false;
    final s = normalize(status);
    if (s.contains('cancel') || s.contains('reject')) return false;
    return isDispatchQueue(status);
  }

  static String dinerOrderCardBadge(String? status) {
    final s = normalize(status);
    if (s.contains('cancel') || s.contains('reject')) return 'Cancelled';
    if (isFulfilled(status)) return 'Delivered';
    if (s.contains('out') || s.contains('assigned') || s.contains('heading')) {
      return 'On the way';
    }
    if (s.contains('ready') || s.contains('packed')) return 'Ready for pickup';
    if (isPendingKitchen(status)) return 'Waiting for chef';
    if (s.contains('prepar')) return 'Preparing';
    if (s.contains('confirm')) return 'Confirmed';
    final raw = status?.trim() ?? '';
    return raw.isEmpty ? 'In the kitchen' : raw;
  }

  /// Diner timeline: 0 kitchen, 1 packed, 2 on the way, 3 delivered. `-1` cancelled.
  static int dinerProgressStep(String? status) {
    final s = normalize(status);
    if (s.contains('cancel') || s.contains('reject')) return -1;
    if (isFulfilled(status)) return 3;
    if (s.contains('out') || s.contains('assigned') || s.contains('heading')) return 2;
    if (s.contains('ready') || s.contains('packed')) return 1;
    return 0;
  }

  static const dinerProgressLabels = ['Kitchen', 'Packed', 'On the way', 'Delivered'];

  static bool canCustomerCancel(String? status) {
    final s = normalize(status);
    if (s.contains('cancel') || s.contains('reject')) return false;
    if (s.contains('delivered') || s.contains('completed')) return false;
    if (s.contains('prepar') ||
        s.contains('ready') ||
        s.contains('out') ||
        s.contains('assigned') ||
        s.contains('heading')) {
      return false;
    }
    return true;
  }

  /// Customer may cancel until the kitchen starts, and not after the slot begins.
  static bool canCustomerCancelOrder(Map<String, dynamic> order, {DateTime? now}) {
    if (!canCustomerCancel(order['status']?.toString())) return false;
    final slotStart = orderSlotStart(order, now: now);
    final current = now ?? DateTime.now();
    if (slotStart != null && !current.isBefore(slotStart)) return false;
    return true;
  }

  /// Confirm → Preparing → Ready for Pickup.
  static String? nextKitchenStatus(String? current) {
    if (isPendingKitchen(current)) return OrderStatus.confirmed;
    final s = normalize(current);
    if (s == 'confirmed') return OrderStatus.preparing;
    if (s == 'preparing') return OrderStatus.readyForPickup;
    return null;
  }

  /// After Ready for Pickup: partners wait for a driver; chef-self goes out;
  /// pickup / dine-in completes at the kitchen.
  static String? nextDispatchStatus(String? current, ServiceType service) {
    final s = normalize(current);
    if (s == 'out for delivery') {
      return service.usesDeliveryPartner ? null : OrderStatus.delivered;
    }

    if (s == 'ready for pickup' || s == 'driver assigned' || s == 'heading to kitchen') {
      switch (service) {
        case ServiceType.deliveryPlatform:
          return null;
        case ServiceType.deliverySelf:
          return OrderStatus.outForDelivery;
        case ServiceType.pickup:
        case ServiceType.dineIn:
          return OrderStatus.delivered;
      }
    }
    return null;
  }

  static String? nextDriverStatus(String? current) {
    if (canDriverMarkHeadingToPickup(current)) return OrderStatus.headingToKitchen;
    if (canDriverConfirmPickup(current)) return OrderStatus.outForDelivery;
    if (canDriverCompleteRun(current)) return OrderStatus.delivered;
    return null;
  }

  Future<void> advanceKitchen({
    required String orderId,
    required String currentStatus,
    String? dispatchPhotoUrl,
  }) async {
    final next = nextKitchenStatus(currentStatus);
    if (next == null) {
      throw Exception('No kitchen transition from "$currentStatus"');
    }
    await _repo.updateOrderStatus(
      orderId: orderId,
      newStatus: next,
      dispatchPhotoUrl: dispatchPhotoUrl,
    );
  }

  Future<void> dispatch({
    required String orderId,
    required String currentStatus,
    required ServiceType service,
  }) async {
    final next = nextDispatchStatus(currentStatus, service);
    if (next == null) {
      if (service == ServiceType.deliveryPlatform) {
        return;
      }
      throw Exception('No dispatch transition from "$currentStatus"');
    }
    await _repo.updateOrderStatus(orderId: orderId, newStatus: next);
    if (next == OrderStatus.delivered) {
      unawaited(AppAnalytics.logOrderDelivered(orderId: orderId));
    }
  }

  Future<bool> acceptDelivery({required String orderId, required String driverId}) {
    return _repo.acceptDelivery(orderId: orderId, driverId: driverId);
  }

  Future<void> advanceDriver({
    required String orderId,
    required String currentStatus,
    String? deliveryOtp,
    String? podPhotoUrl,
  }) async {
    final next = nextDriverStatus(currentStatus);
    if (next == null) {
      throw Exception('No driver transition from "$currentStatus"');
    }
    await _repo.updateOrderStatus(
      orderId: orderId,
      newStatus: next,
      deliveryOtp: deliveryOtp,
      podPhotoUrl: podPhotoUrl,
    );
    if (next == OrderStatus.delivered) {
      unawaited(AppAnalytics.logOrderDelivered(orderId: orderId));
    }
  }

  Future<void> cancel({
    required String orderId,
    String? chefId,
    String reason = 'Cancelled',
  }) {
    return _repo.cancelOrder(orderId: orderId, chefId: chefId, reason: reason);
  }
}
