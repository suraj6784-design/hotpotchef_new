import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/app_role.dart';
import 'package:hotpotchef_new/utils/app_flavor.dart';

/// Compile-time lock: this file is meaningless unless compiled as Partner.
///
/// CI / docs:
/// ```bash
/// flutter test test/app_flavor_partner_compile_test.dart --flavor partner
/// flutter test test/app_flavor_partner_compile_test.dart --dart-define=APP_FLAVOR=partner
/// ```
///
/// A diner-default `flutter test` run skips this file so the existing diner
/// default assertion in `app_flavor_test.dart` stays valid.
void main() {
  const fromFlavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
  const explicit = String.fromEnvironment('APP_FLAVOR');
  final compiledAsPartner = fromFlavor == 'partner' || explicit == 'partner';

  test('partner flavor compiles kAppStorefront as Partner', () {
    expect(
      compiledAsPartner,
      isTrue,
      reason:
          'Run with --flavor partner (or --dart-define=APP_FLAVOR=partner). '
          'FLUTTER_APP_FLAVOR="$fromFlavor" APP_FLAVOR="$explicit"',
    );
    expect(kAppStorefront, AppStorefront.partner);
    expect(kAppStorefront.isPartner, isTrue);
    expect(kAppStorefront.appName, 'HotPotChef Partner');
    expect(kAppStorefront.allowsRole(AppRole.chef), isTrue);
    expect(kAppStorefront.allowsRole(AppRole.driver), isTrue);
    expect(kAppStorefront.allowsRole(AppRole.customer), isFalse);
    expect(
      kAppStorefront.wrongAccountMessage(AppRole.customer),
      contains('HotPotChef'),
    );
  }, skip: compiledAsPartner ? false : 'Requires --flavor partner (see file header)');
}
