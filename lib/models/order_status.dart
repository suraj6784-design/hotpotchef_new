/// Canonical order statuses written to `orders.status`.
class OrderStatus {
  static const pendingChefApproval = 'Pending Chef Approval';
  static const confirmed = 'Confirmed';
  static const preparing = 'Preparing';
  static const readyForPickup = 'Ready for Pickup';
  static const driverAssigned = 'Driver Assigned';
  static const headingToKitchen = 'Heading to Kitchen';
  static const outForDelivery = 'Out for Delivery';
  static const delivered = 'Delivered';
  static const cancelled = 'Cancelled';

  /// Maps a stored label, including older aliases, onto the status we write.
  /// Unknown or empty text stays null so callers do not invent a step.
  static String? canonical(String? raw) {
    final s = raw?.trim().toLowerCase() ?? '';
    if (s.isEmpty || s.contains('timeout')) return null;
    if (s.contains('cancel') || s.contains('reject')) return cancelled;
    if (s.contains('out for delivery') || s.contains('out_for_delivery') || s == 'out') {
      return outForDelivery;
    }
    if (s.contains('delivered') || s.contains('completed') || s == 'fulfilled') return delivered;
    if (s.contains('heading') ||
        s.contains('en route to pickup') ||
        s.contains('on the way to pickup') ||
        s.contains('picked')) {
      return headingToKitchen;
    }
    if (s.contains('assigned') || s == 'accepted' || s.contains('accept')) return driverAssigned;
    if (s.contains('ready') || s.contains('packed')) return readyForPickup;
    if (s.contains('prepar')) return preparing;
    if (s == 'confirmed' || s.contains('confirm')) return confirmed;
    if (s.contains('pending') || s == 'placed' || s == 'new') return pendingChefApproval;
    return null;
  }
}
