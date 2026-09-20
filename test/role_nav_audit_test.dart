import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/app_role.dart';
import 'package:hotpotchef_new/utils/app_flavor.dart';
import 'package:hotpotchef_new/utils/diner_locale.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/utils/legal_content.dart';
import 'package:hotpotchef_new/widgets/app_widgets.dart';

void main() {
  group('canonical role nav helpers', () {
    test('legal chrome uses one GoRouter path per document', () {
      expect(legalPathFor(LegalDocumentType.terms), '/legal/terms');
      expect(legalPathFor(LegalDocumentType.privacy), '/legal/privacy');
      expect(legalPathFor(LegalDocumentType.faq), '/legal/faq');
      expect(legalPathFor(LegalDocumentType.cancellation), '/legal/cancellation');
    });

    test('driver hub honors the same tab query keys as chef', () {
      expect(driverHubTabIndex(null), 0);
      expect(driverHubTabIndex('orders'), 1);
      expect(driverHubTabIndex('profile'), 2);
      expect(driverHubTabIndex('account'), 2);
      expect(driverHubTabIndex('alerts'), 3);
      expect(driverHubTabIndex('notifications'), 3);
    });

    test('inbox and profile deep links land on the dock tab', () {
      expect(roleHubAlertsPath(AppRole.customer), '/customer-hub?tab=alerts');
      expect(roleHubAlertsPath(AppRole.chef), '/chef-hub?tab=alerts');
      expect(roleHubAlertsPath(AppRole.driver), '/driver-hub?tab=alerts');
      expect(roleHubAlertsPath(AppRole.admin), '/notifications');
      expect(roleHubProfilePath(AppRole.chef), '/chef-hub?tab=profile');
      expect(roleHubProfilePath(AppRole.driver), '/driver-hub?tab=profile');
      expect(dinerOrdersPath(), '/customer-hub?tab=orders');
      expect(dinerOrdersPath(past: true), '/customer-hub?tab=orders&past=1');
    });

    test('diner English dock labels match partner dock labels', () {
      final diner = dinerCopy('en');
      final partner = partnerHubDockDestinations(orderBadge: 2);
      expect(diner.home, 'Home');
      expect(diner.orders, 'Orders');
      expect(diner.account, 'Profile');
      expect(diner.notifications, 'Alerts');
      expect(partner.map((d) => d.label), ['Home', 'Orders', 'Profile', 'Alerts']);
      expect(partner[1].badgeCount, 2);
    });
  });

  group('flavor / wrong storefront', () {
    test('diner APK rejects chef and driver accounts', () {
      expect(kAppStorefront, AppStorefront.diner);
      expect(kAppStorefront.allowsRole(AppRole.customer), isTrue);
      expect(kAppStorefront.allowsRole(AppRole.chef), isFalse);
      expect(kAppStorefront.allowsRole(AppRole.driver), isFalse);
      expect(kAppStorefront.allowsRole(AppRole.admin), isTrue);
      expect(
        AppStorefront.diner.wrongAccountMessage(AppRole.chef),
        contains('HotPotChef Partner'),
      );
    });

    test('partner APK rejects diner accounts', () {
      expect(AppStorefront.partner.allowsRole(AppRole.chef), isTrue);
      expect(AppStorefront.partner.allowsRole(AppRole.driver), isTrue);
      expect(AppStorefront.partner.allowsRole(AppRole.customer), isFalse);
      expect(
        AppStorefront.partner.wrongAccountMessage(AppRole.customer),
        contains('HotPotChef'),
      );
      expect(AppStorefront.partner.wrongAccountMessage(AppRole.customer), contains('diner'));
    });
  });

  group('role capabilities that must not leak across hubs', () {
    test('referral is diner-only; packaging is chef-only', () {
      expect(AppRole.customer.usesReferral, isTrue);
      expect(AppRole.chef.usesReferral, isFalse);
      expect(AppRole.driver.usesReferral, isFalse);
      expect(AppRole.chef.canUsePackagingStore, isTrue);
      expect(AppRole.customer.canUsePackagingStore, isFalse);
      expect(AppRole.driver.canUsePackagingStore, isFalse);
    });

    test('KYC and past-order alerts use hub chrome, not a second stack', () {
      expect(isStackAlertPath('/chef-hub?tab=profile'), isFalse);
      expect(isStackAlertPath('/driver-hub?tab=profile'), isFalse);
      expect(isStackAlertPath('/chef-profile'), isFalse);
      expect(isStackAlertPath('/chat/room-1'), isTrue);
    });
  });
}
