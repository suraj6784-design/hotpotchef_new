// lib/utils/route_authz.dart
//
// Pure redirect helpers for GoRouter. Kept free of Flutter/Supabase so the
// role-to-route matrix can be unit-tested without initializing the app.
//
// Role source: JWT `user_metadata.role` (what GoRouter can read synchronously).
// Auth/signup also writes `public.users.role`; if those diverge, the router
// follows metadata until the session is refreshed.
//
// Owner allowlist (`suraj6784@gmail.com`) is treated as Admin even when a leftover
// Chef/Customer JWT is still attached — matching the existing Admin desk gate.

import 'platform_ops_access.dart';

enum AppRole { customer, chef, driver, admin }

enum RouteAccess {
  /// `/auth` — guests only; signed-in users are sent to their hub.
  public,

  /// `/customer-hub` — guests and customers. Chefs/drivers/admins go to their hub.
  guestOrCustomer,

  /// Other `/customer-*` routes (e.g. profile) — customers only; guests → `/auth`.
  customer,

  /// `/chef-*` — chefs only.
  chef,

  /// `/driver-*` — drivers only.
  driver,

  /// `/platform-ops` — admins only (or the owner allowlist email).
  admin,

  /// Chat / tracking — any visitor (customers and drivers both use these).
  shared,
}

abstract final class RouteAuthz {
  static const authPath = '/auth';
  static const customerHub = '/customer-hub';
  static const chefHub = '/chef-hub';
  static const driverHub = '/driver-hub';
  static const platformOps = '/platform-ops';

  static const chefPaths = {
    '/chef-hub',
    '/chef-analytics',
    '/chef-profile',
    '/chef-publish-meal',
  };

  static const driverPaths = {
    '/driver-hub',
    '/driver-profile',
  };

  static const customerOnlyPaths = {
    '/customer-profile',
  };

  static const adminPaths = {
    '/platform-ops',
  };

  /// Normalize signup/DB values (`Chef`, `DRIVER`, `Admin`, ` customer `) to [AppRole].
  /// Unknown or missing values default to customer, matching existing router
  /// and auth-screen fallbacks. The owner allowlist email is always Admin.
  static AppRole parseRole(String? raw, {String? email}) {
    if (isPlatformOwnerEmail(email)) return AppRole.admin;
    switch (raw?.trim().toLowerCase()) {
      case 'chef':
        return AppRole.chef;
      case 'driver':
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

  static String hubForRole(AppRole role) {
    switch (role) {
      case AppRole.chef:
        return chefHub;
      case AppRole.driver:
        return driverHub;
      case AppRole.admin:
        return platformOps;
      case AppRole.customer:
        return customerHub;
    }
  }

  static String normalizePath(String path) {
    if (path.isEmpty) return '/';
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  static RouteAccess classify(String path) {
    final p = normalizePath(path);

    if (p == authPath) return RouteAccess.public;
    if (p == customerHub || p == '/cart' || p == '/app/cart') {
      return RouteAccess.guestOrCustomer;
    }
    if (customerOnlyPaths.contains(p) || p.startsWith('/customer-')) {
      return RouteAccess.customer;
    }
    if (chefPaths.contains(p) || p.startsWith('/chef-')) {
      return RouteAccess.chef;
    }
    if (driverPaths.contains(p) || p.startsWith('/driver-')) {
      return RouteAccess.driver;
    }
    if (adminPaths.contains(p) || p.startsWith('/platform-ops')) {
      return RouteAccess.admin;
    }
    if (p == '/tracking' || p == '/chat' || p.startsWith('/chat/')) {
      return RouteAccess.shared;
    }
    return RouteAccess.shared;
  }

  /// Returns a location to redirect to, or `null` to allow the navigation.
  static String? resolveRedirect({
    required bool isAuthenticated,
    String? rawRole,
    String? email,
    required String path,
  }) {
    final role = parseRole(rawRole, email: email);
    final access = classify(path);
    final hub = hubForRole(role);
    final current = normalizePath(path);

    final String? target;
    if (!isAuthenticated) {
      target = switch (access) {
        RouteAccess.chef ||
        RouteAccess.driver ||
        RouteAccess.customer ||
        RouteAccess.admin =>
          authPath,
        RouteAccess.public || RouteAccess.guestOrCustomer || RouteAccess.shared => null,
      };
    } else {
      target = switch (access) {
        RouteAccess.public => hub,
        RouteAccess.chef => role == AppRole.chef ? null : hub,
        RouteAccess.driver => role == AppRole.driver ? null : hub,
        RouteAccess.admin => role == AppRole.admin ? null : hub,
        RouteAccess.customer || RouteAccess.guestOrCustomer =>
          role == AppRole.customer ? null : hub,
        RouteAccess.shared => null,
      };
    }

    if (target == null || normalizePath(target) == current) return null;
    return target;
  }
}
