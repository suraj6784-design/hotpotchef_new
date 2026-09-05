import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/app_role.dart';

void main() {
  group('roleCanOpenAuthenticatedPath', () {
    test('keeps each role inside its own hub and account screens', () {
      expect(roleCanOpenAuthenticatedPath(AppRole.chef, '/chef-hub'), isTrue);
      expect(roleCanOpenAuthenticatedPath(AppRole.chef, '/chef-hub?tab=supplies'.split('?').first), isTrue);
      expect(roleCanOpenAuthenticatedPath(AppRole.customer, '/chef-hub'), isFalse);
      expect(roleCanOpenAuthenticatedPath(AppRole.driver, '/chef-hub'), isFalse);

      expect(roleCanOpenAuthenticatedPath(AppRole.driver, '/driver-hub'), isTrue);
      expect(roleCanOpenAuthenticatedPath(AppRole.customer, '/driver-hub'), isFalse);
      expect(roleCanOpenAuthenticatedPath(AppRole.chef, '/driver-profile'), isFalse);

      expect(roleCanOpenAuthenticatedPath(AppRole.customer, '/customer-hub'), isTrue);
      expect(roleCanOpenAuthenticatedPath(AppRole.customer, '/bulk-request'), isTrue);
      expect(roleCanOpenAuthenticatedPath(AppRole.chef, '/customer-hub'), isFalse);
      expect(roleCanOpenAuthenticatedPath(AppRole.driver, '/referral'), isFalse);
    });

    test('leaves shared screens open to every signed-in role', () {
      expect(roleCanOpenAuthenticatedPath(AppRole.customer, '/chats'), isTrue);
      expect(roleCanOpenAuthenticatedPath(AppRole.chef, '/tracking'), isTrue);
      expect(roleCanOpenAuthenticatedPath(AppRole.driver, '/meal/abc'), isTrue);
    });
  });
}
