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

  static String? known(String? status) => OrderStatus.canonical(status);

  static bool _is(String? status, String value) => known(status) == value;

  static bool isPendingKitchen(String? status) => _is(status, OrderStatus.pendingChefApproval);

  static bool isKitchenActive(String? status) {
    final knownStatus = known(status);
    return knownStatus == OrderStatus.pendingChefApproval ||
        knownStatus == OrderStatus.confirmed ||
        knownStatus == OrderStatus.preparing;
  }

  /// Unassigned partner jobs drivers may claim: kitchen-ready or orphaned in transit.
  static bool isOpenDriverJob(String? status) {
    if (isKitchenActive(status)) return false;
    return isDispatchQueue(status);
  }

  static bool canDriverStartRun(String? status) {
    final knownStatus = known(status);
    return knownStatus == OrderStatus.readyForPickup || knownStatus == OrderStatus.driverAssigned;
  }

  /// After accept: partner is going to the chef kitchen.
  static bool canDriverMarkHeadingToPickup(String? status) {
    if (isHeadingToPickup(status) || canDriverCompleteRun(status)) return false;
    return canDriverStartRun(status);
  }

  static bool isHeadingToPickup(String? status) => _is(status, OrderStatus.headingToKitchen);

  static bool canDriverConfirmPickup(String? status) => isHeadingToPickup(status);

  static bool canDriverCompleteRun(String? status) => _is(status, OrderStatus.outForDelivery);

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
    switch (known(status)) {
      case OrderStatus.readyForPickup:
      case OrderStatus.driverAssigned:
      case OrderStatus.headingToKitchen:
      case OrderStatus.outForDelivery:
        return true;
      default:
        return false;
    }
  }

  /// Handed to the diner — not "out for delivery".
  static bool isFulfilled(String? status) => _is(status, OrderStatus.delivered);

  /// Diner live map once the partner has the box and is out for delivery.
  static bool isTrackable(String? status) => canDriverCompleteRun(status);

  static String dinerOrderCardBadge(String? status) {
    switch (known(status)) {
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.outForDelivery:
        return 'Out for delivery';
      case OrderStatus.headingToKitchen:
        return 'Partner is heading to the kitchen';
      case OrderStatus.driverAssigned:
        return 'Partner assigned';
      case OrderStatus.readyForPickup:
        return 'Packed';
      case OrderStatus.pendingChefApproval:
        return 'Waiting for the kitchen';
      case OrderStatus.preparing:
        return 'Preparing';
      case OrderStatus.confirmed:
        return 'Kitchen confirmed';
      default:
        final raw = status?.trim() ?? '';
        return raw.isEmpty ? 'In the kitchen' : raw;
    }
  }

  /// Diner timeline: 0 kitchen, 1 packed, 2 on the way, 3 delivered. `-1` cancelled.
  static int dinerProgressStep(String? status) {
    switch (known(status)) {
      case OrderStatus.cancelled:
        return -1;
      case OrderStatus.delivered:
        return 3;
      case OrderStatus.outForDelivery:
      case OrderStatus.driverAssigned:
      case OrderStatus.headingToKitchen:
        return 2;
      case OrderStatus.readyForPickup:
        return 1;
      default:
        return 0;
    }
  }

  static const dinerProgressLabels = ['Kitchen', 'Packed', 'On the way', 'Delivered'];

  static bool canCustomerCancel(String? status) {
    final knownStatus = known(status);
    return knownStatus == OrderStatus.pendingChefApproval || knownStatus == OrderStatus.confirmed;
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
    switch (known(current)) {
      case OrderStatus.pendingChefApproval:
        return OrderStatus.confirmed;
      case OrderStatus.confirmed:
        return OrderStatus.preparing;
      case OrderStatus.preparing:
        return OrderStatus.readyForPickup;
      default:
        return null;
    }
  }

  /// After Ready for Pickup: partners wait for a driver; chef-self goes out;
  /// pickup / dine-in completes at the kitchen.
  static String? nextDispatchStatus(String? current, ServiceType service) {
    final knownStatus = known(current);
    if (knownStatus == OrderStatus.outForDelivery) {
      return service.usesDeliveryPartner ? null : OrderStatus.delivered;
    }

    if (knownStatus == OrderStatus.readyForPickup ||
        knownStatus == OrderStatus.driverAssigned ||
        knownStatus == OrderStatus.headingToKitchen) {
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
