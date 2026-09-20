import 'dart:io';

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

  test('storefrontFromFlavorName treats partner aliases as Partner', () {
    expect(storefrontFromFlavorName('partner'), AppStorefront.partner);
    expect(storefrontFromFlavorName('PARTNER'), AppStorefront.partner);
    expect(storefrontFromFlavorName(' chef '), AppStorefront.partner);
    expect(storefrontFromFlavorName('driver'), AppStorefront.partner);
    expect(storefrontFromFlavorName('diner'), AppStorefront.diner);
    expect(storefrontFromFlavorName(''), AppStorefront.diner);
    expect(storefrontFromFlavorName(null), AppStorefront.diner);
  });

  test('Android Gradle partner flavor injects APP_FLAVOR dart-define', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('fun withStorefrontDartDefine'));
    expect(gradle, contains('APP_FLAVOR=\$flavor'));
    expect(gradle, contains('assertStorefrontFlavorDefines'));
    expect(gradle, contains('create("partner")'));
    expect(gradle, contains('tasks.withType<FlutterTask>()'));
  });
}
