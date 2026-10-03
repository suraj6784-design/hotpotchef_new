// Catalog rows that diners may browse / search.
// Live meals.status is Title Case (`Available`). Archived, Closed, Paused,
// cancelled, and sold-out plates stay out of the public feed and AI search.

abstract final class MealCatalog {
  static const availableStatus = 'Available';

  static const excludedStatuses = <String>{
    'archived',
    'closed',
    'paused',
    'cancelled',
    'canceled',
    'sold out',
    'sold_out',
    'soldout',
  };

  static String _normalize(String? raw) =>
      (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), ' ');

  static bool isAvailableStatus(String? raw) => _normalize(raw) == 'available';

  /// Inventory catalog row (not a legacy "order stored as a meal").
  static bool isSellable(Map<String, dynamic> meal) {
    if (!isAvailableStatus(meal['status']?.toString())) return false;
    final customerName = meal['customer_name']?.toString().trim() ?? '';
    return customerName.isEmpty;
  }
}
