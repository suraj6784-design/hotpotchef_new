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
