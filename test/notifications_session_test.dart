import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/notifications_session.dart';

void main() {
  test('sign-in copy is only for a missing session', () {
    expect(notificationsSignedOutMessage(null), 'Sign in to see notifications.');
    expect(notificationsSignedOutMessage(''), 'Sign in to see notifications.');
    expect(notificationsSignedOutMessage('  '), 'Sign in to see notifications.');
    expect(notificationsSignedOutMessage('diner-1'), isNull);
  });

  test('alerts reload when a session appears after the guest load', () {
    expect(
      notificationsInboxShouldReload(
        settled: true,
        loadedUserId: null,
        sessionUserId: 'diner-1',
      ),
      isTrue,
    );
    expect(
      notificationsInboxShouldReload(
        settled: true,
        loadedUserId: 'diner-1',
        sessionUserId: 'diner-1',
      ),
      isFalse,
    );
    expect(
      notificationsInboxShouldReload(
        settled: true,
        loadedUserId: 'diner-1',
        sessionUserId: null,
      ),
      isTrue,
    );
  });

  test('alerts retry a failed load for the same signed-in user', () {
    expect(
      notificationsInboxShouldReload(
        settled: true,
        loadedUserId: 'diner-1',
        sessionUserId: 'diner-1',
        previousLoadFailed: true,
      ),
      isTrue,
    );
    expect(
      notificationsInboxShouldReload(
        settled: false,
        loadedUserId: null,
        sessionUserId: null,
      ),
      isTrue,
    );
  });
}
