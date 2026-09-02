import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/network.dart';

void main() {
  group('networkErrorMessage', () {
    test('uses timed-out copy for NetworkException and TimeoutException', () {
      expect(
        networkErrorMessage(const NetworkException(NetworkException.timedOutMessage, timedOut: true)),
        NetworkException.timedOutMessage,
      );
      expect(networkErrorMessage(TimeoutException('x')), NetworkException.timedOutMessage);
    });

    test('uses offline copy for socket failures', () {
      expect(
        networkErrorMessage(Exception('SocketException: Failed host lookup')),
        NetworkException.offlineMessage,
      );
    });
  });

  group('WithNetworkTimeout', () {
    test('throws NetworkException when the future hangs', () async {
      await expectLater(
        Completer<void>().future.withTimeout(const Duration(milliseconds: 20)),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
