// test/route_authz_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/route_authz.dart';

void main() {
  group('RouteAuthz.parseRole', () {
    test('normalizes signup/DB casing and whitespace', () {
      expect(RouteAuthz.parseRole('Chef'), AppRole.chef);
      expect(RouteAuthz.parseRole('DRIVER'), AppRole.driver);
      expect(RouteAuthz.parseRole(' customer '), AppRole.customer);
    });

    test('defaults unknown or missing values to customer', () {
      expect(RouteAuthz.parseRole(null), AppRole.customer);
      expect(RouteAuthz.parseRole(''), AppRole.customer);
      expect(RouteAuthz.parseRole('admin'), AppRole.customer);
    });
  });

  group('RouteAuthz.hubForRole', () {
    test('maps each role to its hub', () {
      expect(RouteAuthz.hubForRole(AppRole.customer), '/customer-hub');
      expect(RouteAuthz.hubForRole(AppRole.chef), '/chef-hub');
      expect(RouteAuthz.hubForRole(AppRole.driver), '/driver-hub');
    });
  });

  group('RouteAuthz.classify', () {
    test('groups known routes by role prefix / allowlist', () {
      expect(RouteAuthz.classify('/auth'), RouteAccess.public);
      expect(RouteAuthz.classify('/customer-hub'), RouteAccess.guestOrCustomer);
      expect(RouteAuthz.classify('/customer-profile'), RouteAccess.customer);
      expect(RouteAuthz.classify('/chef-hub'), RouteAccess.chef);
      expect(RouteAuthz.classify('/chef-analytics'), RouteAccess.chef);
      expect(RouteAuthz.classify('/chef-profile'), RouteAccess.chef);
      expect(RouteAuthz.classify('/chef-publish-meal'), RouteAccess.chef);
      expect(RouteAuthz.classify('/driver-hub'), RouteAccess.driver);
      expect(RouteAuthz.classify('/driver-profile'), RouteAccess.driver);
      expect(RouteAuthz.classify('/chat/meal-1'), RouteAccess.shared);
      expect(RouteAuthz.classify('/tracking'), RouteAccess.shared);
    });

    test('future chef/driver/customer paths inherit the prefix group', () {
      expect(RouteAuthz.classify('/chef-new-tool'), RouteAccess.chef);
      expect(RouteAuthz.classify('/driver-id-card'), RouteAccess.driver);
      expect(RouteAuthz.classify('/customer-orders'), RouteAccess.customer);
    });
  });

  group('unauthenticated redirects', () {
    String? guest(String path) => RouteAuthz.resolveRedirect(
          isAuthenticated: false,
          rawRole: null,
          path: path,
        );

    test('sends guests on chef/driver routes to /auth', () {
      for (final path in [
        '/chef-hub',
        '/chef-analytics',
        '/chef-profile',
        '/chef-publish-meal',
        '/driver-hub',
        '/driver-profile',
      ]) {
        expect(guest(path), '/auth', reason: path);
      }
    });

    test('sends guests on customer-only profile to /auth', () {
      expect(guest('/customer-profile'), '/auth');
    });

    test('allows guest access to customer hub and auth', () {
      expect(guest('/customer-hub'), isNull);
      expect(guest('/auth'), isNull);
    });

    test('allows shared chat/tracking without a session', () {
      expect(guest('/chat/abc'), isNull);
      expect(guest('/tracking'), isNull);
    });
  });

  group('authenticated happy-path landing', () {
    test('signed-in users on /auth go to their role hub', () {
      expect(
        RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: 'Chef', path: '/auth'),
        '/chef-hub',
      );
      expect(
        RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: 'Driver', path: '/auth'),
        '/driver-hub',
      );
      expect(
        RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: 'Customer', path: '/auth'),
        '/customer-hub',
      );
    });

    test('each role may stay on their own hub and role routes', () {
      expect(
        RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: 'chef', path: '/chef-hub'),
        isNull,
      );
      expect(
        RouteAuthz.resolveRedirect(
          isAuthenticated: true,
          rawRole: 'chef',
          path: '/chef-publish-meal',
        ),
        isNull,
      );
      expect(
        RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: 'driver', path: '/driver-hub'),
        isNull,
      );
      expect(
        RouteAuthz.resolveRedirect(
          isAuthenticated: true,
          rawRole: 'customer',
          path: '/customer-hub',
        ),
        isNull,
      );
      expect(
        RouteAuthz.resolveRedirect(
          isAuthenticated: true,
          rawRole: 'customer',
          path: '/customer-profile',
        ),
        isNull,
      );
    });
  });

  group('wrong-role redirects', () {
    test('customer cannot open chef or driver routes', () {
      for (final path in [
        '/chef-hub',
        '/chef-analytics',
        '/chef-profile',
        '/chef-publish-meal',
        '/driver-hub',
        '/driver-profile',
      ]) {
        expect(
          RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: 'customer', path: path),
          '/customer-hub',
          reason: path,
        );
      }
    });

    test('chef cannot open driver or customer routes', () {
      expect(
        RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: 'chef', path: '/driver-hub'),
        '/chef-hub',
      );
      expect(
        RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: 'chef', path: '/driver-profile'),
        '/chef-hub',
      );
      expect(
        RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: 'chef', path: '/customer-hub'),
        '/chef-hub',
      );
      expect(
        RouteAuthz.resolveRedirect(
          isAuthenticated: true,
          rawRole: 'chef',
          path: '/customer-profile',
        ),
        '/chef-hub',
      );
    });

    test('driver cannot open chef or customer routes', () {
      expect(
        RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: 'driver', path: '/chef-hub'),
        '/driver-hub',
      );
      expect(
        RouteAuthz.resolveRedirect(
          isAuthenticated: true,
          rawRole: 'driver',
          path: '/chef-analytics',
        ),
        '/driver-hub',
      );
      expect(
        RouteAuthz.resolveRedirect(
          isAuthenticated: true,
          rawRole: 'driver',
          path: '/customer-hub',
        ),
        '/driver-hub',
      );
    });

    test('shared chat and tracking stay available to every role', () {
      for (final role in ['customer', 'chef', 'driver']) {
        expect(
          RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: role, path: '/chat/m1'),
          isNull,
        );
        expect(
          RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: role, path: '/tracking'),
          isNull,
        );
      }
    });
  });

  group('path hygiene', () {
    test('trailing slashes do not bypass role checks', () {
      expect(
        RouteAuthz.resolveRedirect(
          isAuthenticated: true,
          rawRole: 'customer',
          path: '/chef-hub/',
        ),
        '/customer-hub',
      );
    });

    test('does not redirect when already on the computed hub', () {
      expect(
        RouteAuthz.resolveRedirect(isAuthenticated: true, rawRole: 'chef', path: '/chef-hub'),
        isNull,
      );
    });
  });
}
