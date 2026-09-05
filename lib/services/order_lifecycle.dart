import '../models/cart_enums.dart';
import '../models/order_status.dart';
import '../utils/helpers.dart';
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

  static bool canDriverCompleteRun(String? status) {
    final s = normalize(status);
    return s.contains('out') && !s.contains('timeout');
  }

  static bool isDispatchQueue(String? status) {
    final s = normalize(status);
    return s.contains('ready') ||
        s.contains('assigned') ||
        s.contains('out for delivery') ||
        s.contains('out_for_delivery');
  }

  static bool isTrackable(String? status) {
    final s = normalize(status);
    if (s.contains('cancel') || s.contains('reject') || s.contains('delivered') || s.contains('completed')) {
      return false;
    }
    return s.contains('ready') || s.contains('assigned') || s.contains('out');
  }

  static bool canCustomerCancel(String? status) {
    final s = normalize(status);
    if (s.contains('cancel') || s.contains('reject')) return false;
    if (s.contains('delivered') || s.contains('completed')) return false;
    if (s.contains('prepar') || s.contains('ready') || s.contains('out') || s.contains('assigned')) {
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

    if (s == 'ready for pickup' || s == 'driver assigned') {
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
    if (canDriverStartRun(current)) return OrderStatus.outForDelivery;
    if (canDriverCompleteRun(current)) return OrderStatus.delivered;
    return null;
  }

  Future<void> advanceKitchen({required String orderId, required String currentStatus}) async {
    final next = nextKitchenStatus(currentStatus);
    if (next == null) {
      throw Exception('No kitchen transition from "$currentStatus"');
    }
    await _repo.updateOrderStatus(orderId: orderId, newStatus: next);
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
  }

  Future<bool> acceptDelivery({required String orderId, required String driverId}) {
    return _repo.acceptDelivery(orderId: orderId, driverId: driverId);
  }

  Future<void> advanceDriver({required String orderId, required String currentStatus}) async {
    final next = nextDriverStatus(currentStatus);
    if (next == null) {
      throw Exception('No driver transition from "$currentStatus"');
    }
    await _repo.updateOrderStatus(orderId: orderId, newStatus: next);
  }

  Future<void> cancel({
    required String orderId,
    String? chefId,
    String reason = 'Cancelled',
  }) {
    return _repo.cancelOrder(orderId: orderId, chefId: chefId, reason: reason);
  }
}
