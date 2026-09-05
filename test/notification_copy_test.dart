import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/utils/notification_copy.dart';

void main() {
  test('mealTitleFromItems reads cart JSON and list maps', () {
    expect(
      mealTitleFromItems('[{"title":"Dal Tadka","quantity":1}]'),
      'Dal Tadka',
    );
    expect(
      mealTitleFromItems([
        {'name': 'Poha'},
      ]),
      'Poha',
    );
    expect(mealTitleFromItems(null), 'your order');
  });

  test('new paid order alerts the chef, not the customer', () {
    final copy = orderAlertCopy(
      status: 'Pending Chef Approval',
      isInsert: true,
      mealTitle: 'Dal Tadka',
    );
    expect(copy, isNotNull);
    expect(copy!.notifyChef, isTrue);
    expect(copy.notifyCustomer, isFalse);
    expect(copy.title, 'New order');
    expect(copy.body, contains('Dal Tadka'));
  });

  test('kitchen and cancel updates use distinct audiences', () {
    final confirmed = orderAlertCopy(
      status: 'Confirmed',
      isInsert: false,
      previousStatus: 'Pending Chef Approval',
      mealTitle: 'Rice',
    );
    expect(confirmed!.notifyCustomer, isTrue);
    expect(confirmed.notifyChef, isFalse);

    final cancelled = orderAlertCopy(
      status: 'Cancelled',
      isInsert: false,
      previousStatus: 'Pending Chef Approval',
      mealTitle: 'Rice',
    );
    expect(cancelled!.notifyChef, isTrue);
    expect(cancelled.notifyCustomer, isTrue);
    expect(cancelled.title, 'Order cancelled');

    final ready = orderAlertCopy(
      status: 'Ready for Pickup',
      isInsert: false,
      previousStatus: 'Preparing',
      mealTitle: 'Rice',
    );
    expect(ready!.notifyDriver, isTrue);
    expect(ready.notifyCustomer, isTrue);
  });

  test('unchanged status is silent', () {
    expect(
      orderAlertCopy(
        status: 'Preparing',
        isInsert: false,
        previousStatus: 'Preparing',
      ),
      isNull,
    );
  });

  test('chat preview truncates long messages', () {
    expect(chatPreview('  hello  '), 'hello');
    expect(chatPreview('x' * 90).endsWith('...'), isTrue);
    expect(chatPreview(''), contains('New message'));
  });

  test('order group alert title uses the Order#', () {
    expect(orderGroupAlertTitle('aaaaaaaa-bbbb-cccc'), 'Order AAAAAAAA');
    expect(orderGroupAlertTitle(''), 'New message');
  });

  test('new catering broadcast alerts kitchens, not the customer', () {
    final copy = leadAlertCopy(
      status: 'Open',
      isInsert: true,
      title: 'Office lunch',
    );
    expect(copy, isNotNull);
    expect(copy!.notifyAllChefs, isTrue);
    expect(copy.notifyCustomer, isFalse);
    expect(copy.body, contains('Office lunch'));
  });

  test('claimed lead alerts the customer; cancel alerts the chef', () {
    final claimed = leadAlertCopy(
      status: 'Accepted',
      isInsert: false,
      previousStatus: 'Open',
      title: 'Office lunch',
    );
    expect(claimed!.notifyCustomer, isTrue);
    expect(claimed.notifyAllChefs, isFalse);

    final cancelled = leadAlertCopy(
      status: 'Cancelled',
      isInsert: false,
      previousStatus: 'Accepted',
      title: 'Office lunch',
    );
    expect(cancelled!.notifyClaimedChef, isTrue);
    expect(cancelled.notifyCustomer, isFalse);
  });

  test('inbox lists only Order# groups that already have a message', () {
    final rooms = mergeChatInboxRooms(
      myId: 'cust',
      orders: [
        {
          'id': 'order-uuid',
          'order_id': 'ABC12345-xyz',
          'customer_id': 'cust',
          'chef_id': 'chef',
          'created_at': '2026-01-01T00:00:00Z',
        },
        {
          'id': 'silent-order',
          'order_id': 'SILENT01-xyz',
          'customer_id': 'cust',
          'chef_id': 'chef',
          'created_at': '2026-01-01T01:00:00Z',
        },
      ],
      requests: [
        {
          'id': 'req-1',
          'title': 'Office lunch',
          'customer_id': 'cust',
          'accepted_chef_id': 'chef',
          'created_at': '2026-01-02T00:00:00Z',
        },
      ],
      messages: [
        {
          'meal_id': 'ABC12345-xyz',
          'content': 'On the way',
          'created_at': '2026-01-03T10:00:00Z',
          'sender_id': 'chef',
        },
      ],
    );

    expect(rooms, hasLength(1));
    expect(rooms.first.title, 'Order ABC12345');
    expect(rooms.first.preview, 'On the way');
    expect(rooms.any((room) => room.title == 'Office lunch'), isFalse);
  });

  test('inbox lists a catering chat after the first message', () {
    final rooms = mergeChatInboxRooms(
      myId: 'cust',
      orders: const [],
      requests: [
        {
          'id': 'req-1',
          'title': 'Office lunch',
          'customer_id': 'cust',
          'accepted_chef_id': 'chef',
          'created_at': '2026-01-02T00:00:00Z',
        },
      ],
      messages: [
        {
          'meal_id': 'req-1',
          'content': 'We can do 40 plates',
          'created_at': '2026-01-03T10:00:00Z',
          'sender_id': 'chef',
        },
      ],
    );
    expect(rooms, hasLength(1));
    expect(rooms.first.title, 'Office lunch');
    expect(rooms.first.preview, 'We can do 40 plates');
  });

  test('inbox keeps a sent message that has no matching order', () {
    final rooms = mergeChatInboxRooms(
      myId: 'cust',
      orders: const [],
      requests: const [],
      messages: [
        {
          'meal_id': 'legacy-room',
          'content': 'Still there?',
          'created_at': '2026-01-04T00:00:00Z',
        },
      ],
    );
    expect(rooms, hasLength(1));
    expect(rooms.first.roomId, 'legacy-room');
    expect(rooms.first.preview, 'Still there?');
  });
}
