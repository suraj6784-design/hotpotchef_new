// lib/utils/order_status.dart
//
// Canonical fulfillment statuses are snake_case. Chef used to write Title
// Case ("Ready for Pickup") while the driver app wrote snake_case
// (`ready_for_pickup`), so push targeting and status equality checks missed
// each other. [parse] accepts both forms during the transition.

import '../models/cart_enums.dart';

enum OrderStatus {
  pendingChefApproval,
  confirmed,
  preparing,
  readyForPickup,
  driverAssigned,
  accepted,
  pickedUp,
  outForDelivery,
  delivered,
  cancelled,
  completed,
  unknown;

  /// snake_case persisted on `orders.status`.
  String get canonical {
    switch (this) {
      case OrderStatus.pendingChefApproval:
        return 'pending_chef_approval';
      case OrderStatus.confirmed:
        return 'confirmed';
      case OrderStatus.preparing:
        return 'preparing';
      case OrderStatus.readyForPickup:
        return 'ready_for_pickup';
      case OrderStatus.driverAssigned:
        return 'driver_assigned';
      case OrderStatus.accepted:
        return 'accepted';
      case OrderStatus.pickedUp:
        return 'picked_up';
      case OrderStatus.outForDelivery:
        return 'out_for_delivery';
      case OrderStatus.delivered:
        return 'delivered';
      case OrderStatus.cancelled:
        return 'cancelled';
      case OrderStatus.completed:
        return 'completed';
      case OrderStatus.unknown:
        return 'unknown';
    }
  }

  /// Title Case label for badges and snackbars.
  String get displayLabel {
    switch (this) {
      case OrderStatus.pendingChefApproval:
        return 'Pending Chef Approval';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.preparing:
        return 'Preparing';
      case OrderStatus.readyForPickup:
        return 'Ready for Pickup';
      case OrderStatus.driverAssigned:
        return 'Driver Assigned';
      case OrderStatus.accepted:
        return 'Accepted';
      case OrderStatus.pickedUp:
        return 'Picked Up';
      case OrderStatus.outForDelivery:
        return 'Out for Delivery';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.unknown:
        return 'Unknown';
    }
  }

  bool get isKitchenQueue =>
      this == OrderStatus.pendingChefApproval ||
      this == OrderStatus.confirmed ||
      this == OrderStatus.preparing;

  bool get isDispatchQueue =>
      this == OrderStatus.readyForPickup || this == OrderStatus.outForDelivery;

  bool get isDeliveredLike =>
      this == OrderStatus.delivered || this == OrderStatus.completed;

  /// Parses Title Case, snake_case, kebab-case, and a few historical aliases.
  static OrderStatus parse(String? raw) {
    final normalized = _normalize(raw);
    if (normalized.isEmpty) return OrderStatus.unknown;

    switch (normalized) {
      case 'pendingchefapproval':
      case 'pending':
        return OrderStatus.pendingChefApproval;
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'preparing':
        return OrderStatus.preparing;
      case 'readyforpickup':
      case 'ready':
        return OrderStatus.readyForPickup;
      case 'driverassigned':
        return OrderStatus.driverAssigned;
      case 'accepted':
        return OrderStatus.accepted;
      case 'pickedup':
      case 'picked':
        return OrderStatus.pickedUp;
      case 'outfordelivery':
      case 'out':
        return OrderStatus.outForDelivery;
      case 'delivered':
        return OrderStatus.delivered;
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return OrderStatus.cancelled;
      case 'completed':
        return OrderStatus.completed;
      default:
        return OrderStatus.unknown;
    }
  }

  /// Value to persist. Unknown raw strings are snake_cased rather than dropped.
  static String toCanonical(String? raw) {
    final parsed = parse(raw);
    if (parsed != OrderStatus.unknown) return parsed.canonical;
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    return trimmed.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
  }

  static String toDisplay(String? raw) {
    final parsed = parse(raw);
    if (parsed != OrderStatus.unknown) return parsed.displayLabel;
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? 'Unknown' : trimmed;
  }

  static bool hasAssignedDriver(Map<String, dynamic> order) {
    final driver = order['driver_id'] ?? order['delivery_partner_id'];
    if (driver == null) return false;
    final id = driver.toString().trim();
    return id.isNotEmpty && id.toLowerCase() != 'null';
  }

  /// Platform delivery needs a claimed driver before "Out for Delivery".
  /// Self-delivery / pickup / dine-in can be dispatched by the chef.
  static bool canMarkOutForDelivery(Map<String, dynamic> order) {
    if (hasAssignedDriver(order)) return true;
    final svc = ServiceType.fromString(order['service_type']?.toString());
    return svc != ServiceType.deliveryPlatform;
  }

  static String _normalize(String? value) {
    return (value ?? '').toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
