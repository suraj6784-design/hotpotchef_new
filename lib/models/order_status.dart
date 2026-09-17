/// Canonical order statuses written to `orders.status`.
class OrderStatus {
  static const pendingChefApproval = 'Pending Chef Approval';
  static const confirmed = 'Confirmed';
  static const preparing = 'Preparing';
  static const readyForPickup = 'Ready for Pickup';
  static const driverAssigned = 'Driver Assigned';
  static const outForDelivery = 'Out for Delivery';
  static const delivered = 'Delivered';
  static const cancelled = 'Cancelled';
}
