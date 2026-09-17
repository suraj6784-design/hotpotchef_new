import '../models/app_role.dart';

/// Compile-time storefront. `diner` is HotPotChef; `partner` is HotPotChef Partner.
enum AppStorefront { diner, partner }

AppStorefront get kAppStorefront {
  const raw = String.fromEnvironment('APP_FLAVOR', defaultValue: 'diner');
  switch (raw.trim().toLowerCase()) {
    case 'partner':
    case 'chef':
    case 'driver':
      return AppStorefront.partner;
    default:
      return AppStorefront.diner;
  }
}

extension AppStorefrontX on AppStorefront {
  bool get isPartner => this == AppStorefront.partner;
  bool get isDiner => this == AppStorefront.diner;

  String get appName => isPartner ? 'HotPotChef Partner' : 'HotPotChef';

  String get otherAppName => isPartner ? 'HotPotChef' : 'HotPotChef Partner';

  List<AppRole> get signupRoles => isPartner
      ? const [AppRole.chef, AppRole.driver]
      : const [AppRole.customer];

  bool allowsRole(AppRole role) {
    if (role == AppRole.admin) return true;
    return signupRoles.contains(role);
  }

  String wrongAccountMessage(AppRole role) {
    if (isPartner && role == AppRole.customer) {
      return 'This account is a diner. Install HotPotChef (not Partner) to order.';
    }
    if (isDiner && (role == AppRole.chef || role == AppRole.driver)) {
      return 'Kitchen and delivery accounts use HotPotChef Partner. Install that app to continue.';
    }
    return 'This account does not belong in $appName. Use $otherAppName.';
  }
}
