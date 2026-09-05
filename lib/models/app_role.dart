/// Role selected at signup / stored on the user record.
enum AppRole {
  customer,
  chef,
  driver;

  String get storageValue {
    switch (this) {
      case AppRole.customer:
        return 'Customer';
      case AppRole.chef:
        return 'Chef';
      case AppRole.driver:
        return 'Driver';
    }
  }

  /// Only diners invite friends and earn on a first customer order.
  bool get usesReferral => this == AppRole.customer;

  /// Kitchen supply requests are chef-only. Diners and drivers never use this store.
  bool get canUsePackagingStore => this == AppRole.chef;

  String get hubPath {
    switch (this) {
      case AppRole.customer:
        return '/customer-hub';
      case AppRole.chef:
        return '/chef-hub';
      case AppRole.driver:
        return '/driver-hub';
    }
  }

  static AppRole parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'chef':
      case 'cook':
        return AppRole.chef;
      case 'driver':
      case 'delivery partner':
      case 'delivery_partner':
        return AppRole.driver;
      default:
        return AppRole.customer;
    }
  }
}

const kChefOnlyRoutes = {
  '/chef-hub',
  '/chef-analytics',
  '/chef-profile',
  '/chef-publish-meal',
};

const kDriverOnlyRoutes = {
  '/driver-hub',
  '/driver-profile',
  '/driver-id-card',
};

const kCustomerAccountRoutes = {
  '/customer-hub',
  '/customer-profile',
  '/referral',
  '/order-history',
  '/bulk-request',
};

/// Signed-in users may only open the hub and account screens for their role.
bool roleCanOpenAuthenticatedPath(AppRole role, String path) {
  if (kChefOnlyRoutes.contains(path)) return role == AppRole.chef;
  if (kDriverOnlyRoutes.contains(path)) return role == AppRole.driver;
  if (kCustomerAccountRoutes.contains(path)) return role == AppRole.customer;
  return true;
}
