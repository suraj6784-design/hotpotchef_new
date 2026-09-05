import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  test('kitchen live flag reads bool and string columns', () {
    expect(isKitchenLiveStreaming({'is_live': true}), isTrue);
    expect(isKitchenLiveStreaming({'isLive': '1'}), isTrue);
    expect(isKitchenLiveStreaming({'is_live': false}), isFalse);
    expect(isKitchenLiveStreaming({}), isFalse);
    expect(isKitchenLiveStreaming(null), isFalse);
  });

  test('a kitchen clip expires after two minutes so the next diners can watch', () {
    final started = DateTime.utc(2026, 9, 6, 10, 0, 0);
    expect(
      kitchenLiveRemaining(startedAt: started, now: started.add(const Duration(seconds: 45))),
      const Duration(seconds: 75),
    );
    expect(
      kitchenLiveCountdownLabel(const Duration(seconds: 75)),
      '1:15',
    );
    expect(
      kitchenLiveCanAdmitViewer(startedAt: started, now: started.add(const Duration(seconds: 100))),
      isTrue,
    );
    expect(
      kitchenLiveCanAdmitViewer(startedAt: started, now: started.add(const Duration(seconds: 110))),
      isFalse,
    );
    expect(
      isKitchenLiveStreaming(
        {'is_live': true, 'live_started_at': started.toIso8601String()},
        now: started.add(const Duration(minutes: 3)),
      ),
      isFalse,
    );
    expect(
      isKitchenLiveStreaming(
        {'is_live': true, 'live_started_at': started.toIso8601String()},
        now: started.add(const Duration(seconds: 30)),
      ),
      isTrue,
    );
  });

  test('only that chef can host their kitchen live', () {
    expect(canHostKitchenLive(chefId: 'chef-1', userId: 'chef-1'), isTrue);
    expect(canHostKitchenLive(chefId: 'chef-1', userId: 'diner-2'), isFalse);
    expect(canHostKitchenLive(chefId: 'chef-1', userId: null), isFalse);
    expect(canHostKitchenLive(chefId: '', userId: ''), isFalse);
  });

  test('signed-in diners keep their user id and guests get a guest id', () {
    expect(kitchenLiveViewerId(userId: 'diner-9'), 'diner-9');
    expect(kitchenLiveViewerId(userId: '  '), startsWith('guest-'));
    expect(kitchenLiveViewerId(), startsWith('guest-'));
  });

  test('signaling ignores own rows and other viewers', () {
    expect(
      kitchenLiveSignalForMe(myId: 'chef-1', senderId: 'diner-2', targetId: 'chef-1'),
      isTrue,
    );
    expect(
      kitchenLiveSignalForMe(myId: 'diner-2', senderId: 'chef-1', targetId: ''),
      isTrue,
    );
    expect(
      kitchenLiveSignalForMe(myId: 'diner-2', senderId: 'diner-2', targetId: 'chef-1'),
      isFalse,
    );
    expect(
      kitchenLiveSignalForMe(myId: 'diner-2', senderId: 'chef-1', targetId: 'diner-9'),
      isFalse,
    );
  });

  test('live path keeps host and diner routes distinct', () {
    expect(kitchenLivePath('chef-1'), '/kitchen-live/chef-1');
    expect(kitchenLivePath('chef-1', host: true), '/kitchen-live/chef-1?host=1');
    expect(
      kitchenLivePath('chef-1', chefName: 'Asha Kitchen'),
      '/kitchen-live/chef-1?name=${Uri.encodeQueryComponent('Asha Kitchen')}',
    );
  });

  test('packed box photo copy is only for a real kitchen shot', () {
    expect(hasDispatchPhoto({'dispatch_photo_url': 'https://cdn.example/box.jpg'}), isTrue);
    expect(hasDispatchPhoto({'dispatch_photo_url': ''}), isFalse);
    expect(
      dispatchPackedLabel(takenAt: DateTime.now().subtract(const Duration(seconds: 20))),
      'Your box is packed · just now',
    );
  });

  test('cooked meal copy stays readable', () {
    expect(cookedMealsLabel(0), 'New kitchen');
    expect(cookedMealsLabel(1), 'Cooked 1 meal');
    expect(cookedMealsLabel(12), 'Cooked 12 meals');
  });
}
