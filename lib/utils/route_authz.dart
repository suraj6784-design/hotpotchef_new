// lib/utils/route_authz.dart
//
// Pure redirect helpers for GoRouter. Kept free of Flutter/Supabase so the
// role-to-route matrix can be unit-tested without initializing the app.
//
// Role source: JWT `user_metadata.role` (what GoRouter can read synchronously).
// Auth/signup also writes `public.users.role`; if those diverge, the router
// follows metadata until the session is refreshed.

enum AppRole { customer, chef, driver }

enum RouteAccess {
  /// `/auth` — guests only; signed-in users are sent to their hub.
  public,

  /// `/customer-hub` — guests and customers. Chefs/drivers go to their hub.
  guestOrCustomer,

  /// Other `/customer-*` routes (e.g. profile) — customers only; guests → `/auth`.
  customer,

  /// `/chef-*` — chefs only.
  chef,

  /// `/driver-*` — drivers only.
  driver,

  /// Chat / tracking — any visitor (customers and drivers both use these).
  shared,
}

abstract final class RouteAuthz {
  static const authPath = '/auth';
  static const customerHub = '/customer-hub';
  static const chefHub = '/chef-hub';
  static const driverHub = '/driver-hub';

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

  /// Normalize signup/DB values (`Chef`, `DRIVER`, ` customer `) to [AppRole].
  /// Unknown or missing values default to customer, matching existing router
  /// and auth-screen fallbacks.
  static AppRole parseRole(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'chef':
        return AppRole.chef;
      case 'driver':
        return AppRole.driver;
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
    if (p == customerHub) return RouteAccess.guestOrCustomer;
    if (customerOnlyPaths.contains(p) || p.startsWith('/customer-')) {
      return RouteAccess.customer;
    }
    if (chefPaths.contains(p) || p.startsWith('/chef-')) {
      return RouteAccess.chef;
    }
    if (driverPaths.contains(p) || p.startsWith('/driver-')) {
      return RouteAccess.driver;
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
    required String path,
  }) {
    final role = parseRole(rawRole);
    final access = classify(path);
    final hub = hubForRole(role);
    final current = normalizePath(path);

    final String? target;
    if (!isAuthenticated) {
      target = switch (access) {
        RouteAccess.chef || RouteAccess.driver || RouteAccess.customer => authPath,
        RouteAccess.public || RouteAccess.guestOrCustomer || RouteAccess.shared => null,
      };
    } else {
      target = switch (access) {
        RouteAccess.public => hub,
        RouteAccess.chef => role == AppRole.chef ? null : hub,
        RouteAccess.driver => role == AppRole.driver ? null : hub,
        RouteAccess.customer || RouteAccess.guestOrCustomer =>
          role == AppRole.customer ? null : hub,
        RouteAccess.shared => null,
      };
    }

    if (target == null || normalizePath(target) == current) return null;
    return target;
  }
}
