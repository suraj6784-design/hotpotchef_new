import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/app_role.dart';
import 'package:hotpotchef_new/utils/app_flavor.dart';

String _encodeDartDefine(String entry) => base64.encode(utf8.encode(entry));

List<String> _decodeDartDefines(String? encodedList) {
  if (encodedList == null || encodedList.trim().isEmpty) return const [];
  return encodedList.split(',').map((token) {
    final trimmed = token.trim();
    try {
      return utf8.decode(base64.decode(trimmed));
    } on FormatException {
      return trimmed;
    }
  }).toList();
}

String? _withStorefrontDartDefine(String? existing, String? flavorName) {
  final flavor = flavorName?.trim() ?? '';
  if (flavor != 'diner' && flavor != 'partner') return existing;
  if (_decodeDartDefines(existing).any((e) => e.startsWith('APP_FLAVOR='))) {
    return existing;
  }
  final encoded = _encodeDartDefine('APP_FLAVOR=$flavor');
  if (existing == null || existing.isEmpty) return encoded;
  return '$existing,$encoded';
}

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

  test('Android Gradle partner flavor injects APP_FLAVOR at execution time', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('fun withStorefrontDartDefine'));
    expect(gradle, contains('fun storefrontFlavorCompiled'));
    expect(gradle, contains('assertStorefrontFlavorDefines'));
    expect(gradle, contains('create("partner")'));
    expect(gradle, contains('tasks.withType<FlutterTask>()'));
    expect(gradle, contains('doFirst'));
    expect(
      gradle,
      contains('dartDefines = withStorefrontDartDefine(dartDefines, flavor)'),
    );
    // Configuration-time assignment is overwritten by FlutterPlugin.register.
    expect(
      gradle,
      isNot(contains('configureEach {\n    dartDefines = withStorefrontDartDefine')),
    );
  });

  test('execution-time inject appends APP_FLAVOR onto Flutter partner defines', () {
    // Same shape as the Windows compileFlutterBuildPartnerDebug failure:
    // FLUTTER_APP_FLAVOR=partner is present; APP_FLAVOR is not.
    final flutterDefines = [
      'FLUTTER_APP_FLAVOR=partner',
      'FLUTTER_VERSION=3.44.8',
    ].map(_encodeDartDefine).join(',');
    expect(_decodeDartDefines(flutterDefines), isNot(contains('APP_FLAVOR=partner')));

    // Config-time inject then Flutter overwrite (the bug).
    var dartDefines = _withStorefrontDartDefine(null, 'partner');
    dartDefines = flutterDefines;
    expect(_decodeDartDefines(dartDefines), isNot(contains('APP_FLAVOR=partner')));

    // doFirst inject after Flutter set dartDefines (the fix).
    final injected = _withStorefrontDartDefine(flutterDefines, 'partner');
    expect(_decodeDartDefines(injected), contains('APP_FLAVOR=partner'));
    expect(_decodeDartDefines(injected), contains('FLUTTER_APP_FLAVOR=partner'));
    expect(_withStorefrontDartDefine(injected, 'partner'), injected);
  });
}
