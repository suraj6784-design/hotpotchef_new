import '../models/app_role.dart';

/// Compile-time storefront. `diner` is HotPotChef; `partner` is HotPotChef Partner.
///
/// Resolution (first non-empty wins):
/// 1. Flutter `--flavor` / Android `productFlavors` via `FLUTTER_APP_FLAVOR`
///    (injected automatically; also mirrored as `APP_FLAVOR` from Gradle)
/// 2. Explicit `--dart-define=APP_FLAVOR=...` (release scripts, tests)
/// 3. Default `diner`
enum AppStorefront { diner, partner }

/// Maps a raw flavor / dart-define string to a storefront. Exposed for tests.
AppStorefront storefrontFromFlavorName(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'partner':
    case 'chef':
    case 'driver':
      return AppStorefront.partner;
    default:
      return AppStorefront.diner;
  }
}

AppStorefront get kAppStorefront {
  const fromFlavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
  const explicit = String.fromEnvironment('APP_FLAVOR');
  return storefrontFromFlavorName(fromFlavor.isNotEmpty ? fromFlavor : explicit);
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
