// lib/utils/app_deep_links.dart
//
// Pure URI / auth-event → GoRouter location mapping. Kept free of Flutter
// plugins so unit tests can cover cart and password-recovery deep links.

import 'package:supabase_flutter/supabase_flutter.dart';

import 'route_authz.dart';
import 'store_links.dart';

abstract final class AppDeepLinks {
  static const cartLocation = '/app/cart';
  static const cartLocationAlias = '/cart';
  static const resetPasswordLocation = RouteAuthz.resetPasswordPath;

  /// Maps an incoming app / auth URI to a router location, or `null`.
  static String? locationFor(Uri uri) {
    if (isCartLink(uri)) return cartLocation;
    if (isPasswordResetCallback(uri)) return resetPasswordLocation;
    return null;
  }

  /// Cart tab: prefer `/app/cart`, but bounce to `/cart` when already there so
  /// a second intent remounts [CustomerHubScreen] on tab 1.
  static String cartLocationFor({String? currentPath}) {
    final current = RouteAuthz.normalizePath(currentPath ?? '');
    if (current == cartLocation) return cartLocationAlias;
    return cartLocation;
  }

  static String? locationForAuthEvent(AuthChangeEvent event) {
    if (event == AuthChangeEvent.passwordRecovery) {
      return resetPasswordLocation;
    }
    return null;
  }

  static bool isCartLink(Uri uri) {
    final path = RouteAuthz.normalizePath(uri.path);
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();

    if (scheme == StoreLinks.appScheme) {
      if (host == StoreLinks.appHost &&
          (path == StoreLinks.cartPath || path == cartLocation)) {
        return true;
      }
      if (host.isEmpty && path == cartLocation) {
        return true;
      }
    }

    return path == cartLocation;
  }

  static bool isPasswordResetCallback(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = RouteAuthz.normalizePath(uri.path);

    if (scheme == StoreLinks.passwordResetScheme &&
        host == StoreLinks.passwordResetHost) {
      return true;
    }
    if (path == RouteAuthz.resetCallbackPath) {
      return true;
    }

    final type = uri.queryParameters['type'] ?? fragmentParams(uri)['type'];
    return type == 'recovery';
  }

  static Map<String, String> fragmentParams(Uri uri) {
    final fragment = uri.fragment;
    if (fragment.isEmpty) return const {};
    return Uri.splitQueryString(fragment);
  }

  static String passwordResetRedirectTo() {
    return '${StoreLinks.passwordResetScheme}://${StoreLinks.passwordResetHost}/';
  }
}
