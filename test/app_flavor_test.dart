import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/app_role.dart';
import 'package:hotpotchef_new/utils/app_flavor.dart';

void main() {
  test('default storefront is the diner HotPotChef app', () {
    expect(kAppStorefront, AppStorefront.diner);
    expect(kAppStorefront.appName, 'HotPotChef');
    expect(kAppStorefront.allowsRole(AppRole.customer), isTrue);
    expect(kAppStorefront.allowsRole(AppRole.chef), isFalse);
    expect(kAppStorefront.allowsRole(AppRole.admin), isTrue);
  });

  test('partner storefront copy names the diner app', () {
    expect(AppStorefront.partner.appName, 'HotPotChef Partner');
    expect(AppStorefront.partner.allowsRole(AppRole.driver), isTrue);
    expect(AppStorefront.partner.allowsRole(AppRole.customer), isFalse);
    expect(AppStorefront.partner.wrongAccountMessage(AppRole.customer), contains('HotPotChef'));
  });

  test('FLUTTER_APP_FLAVOR from --flavor partner is enough without APP_FLAVOR', () {
    expect(parseAppStorefront('', 'partner'), AppStorefront.partner);
    expect(parseAppStorefront('diner', 'partner'), AppStorefront.diner);
    expect(parseAppStorefront('partner', ''), AppStorefront.partner);
    expect(parseAppStorefront('', ''), AppStorefront.diner);
  });
}
