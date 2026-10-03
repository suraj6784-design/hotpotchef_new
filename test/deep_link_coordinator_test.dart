import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/services/deep_link_coordinator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('initial URI and stream events navigate to mapped locations', () async {
    final links = StreamController<Uri>.broadcast();
    final destinations = <String>[];
    final coordinator = DeepLinkCoordinator(
      navigate: destinations.add,
      currentPath: () => '/customer-hub',
      linkStream: links.stream,
      getInitialUri: () async => Uri.parse('hotpotchef://app/cart'),
    );

    await coordinator.start();
    expect(destinations, ['/app/cart']);

    links.add(Uri.parse('io.supabase.hotpotchef://reset-callback/'));
    await Future<void>.delayed(Duration.zero);
    expect(destinations, ['/app/cart', '/reset-password']);

    await coordinator.dispose();
    await links.close();
  });

  test('second cart intent while already on /app/cart uses /cart', () async {
    final destinations = <String>[];
    String current = '/app/cart';
    final coordinator = DeepLinkCoordinator(
      navigate: (location) {
        destinations.add(location);
        current = location;
      },
      currentPath: () => current,
    );

    coordinator.handleUri(Uri.parse('hotpotchef://app/cart'));
    expect(destinations, ['/cart']);
  });

  test('passwordRecovery auth event opens the reset screen', () {
    final destinations = <String>[];
    final coordinator = DeepLinkCoordinator(navigate: destinations.add);

    coordinator.handleAuthEvent(AuthChangeEvent.signedIn);
    coordinator.handleAuthEvent(AuthChangeEvent.passwordRecovery);
    expect(destinations, ['/reset-password']);
  });

  test('ignores unrelated URIs', () {
    final destinations = <String>[];
    final coordinator = DeepLinkCoordinator(navigate: destinations.add);

    coordinator.handleUri(Uri.parse('https://hotpotchef.app/customer-hub'));
    expect(destinations, isEmpty);
  });
}
