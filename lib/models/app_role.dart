/// Role selected at signup / stored on the user record.
enum AppRole {
  customer,
  chef,
  driver,
  admin;

  String get storageValue {
    switch (this) {
      case AppRole.customer:
        return 'Customer';
      case AppRole.chef:
        return 'Chef';
      case AppRole.driver:
        return 'Driver';
      case AppRole.admin:
        return 'Admin';
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
      case AppRole.admin:
        return '/platform-ops';
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
      case 'admin':
      case 'ops':
      case 'platform':
      case 'platform admin':
      case 'platform_admin':
        return AppRole.admin;
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
  '/chef-academy',
  '/chef-advertise',
};

const kDriverOnlyRoutes = {
  '/driver-hub',
  '/driver-profile',
  '/driver-id-card',
};

const kCustomerAccountRoutes = {
  '/customer-hub',
  '/customer-profile',
  '/customer-plans',
  '/referral',
  '/order-history',
  '/bulk-request',
  '/support-tickets',
};

const kAdminOnlyRoutes = {
  '/platform-ops',
};

/// Signed-in users may only open the hub and account screens for their role.
bool roleCanOpenAuthenticatedPath(AppRole role, String path) {
  // Helpers (chef/customer/driver with ops seat) still need the desk.
  if (path == '/platform-ops' || path == '/ops-invite') return true;
  if (kAdminOnlyRoutes.contains(path)) return role == AppRole.admin;
  if (kChefOnlyRoutes.contains(path)) return role == AppRole.chef;
  if (kDriverOnlyRoutes.contains(path)) return role == AppRole.driver;
  if (kCustomerAccountRoutes.contains(path)) return role == AppRole.customer;
  return true;
}
