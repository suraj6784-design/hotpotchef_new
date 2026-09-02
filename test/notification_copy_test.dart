import 'package:flutter_test/flutter_test.dart';
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
}
