import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/support.dart';

void main() {
  test('email subject includes the visible order number', () {
    expect(
      supportContactSubject(orderNumber: 'OCB30688'),
      'HotPotChef support — Order OCB30688',
    );
  });

  test('support message links the conversation to that order', () {
    final message = supportContactMessage(
      orderNumber: 'OCB30688',
      orderUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    );
    expect(message, contains('order OCB30688'));
    expect(message, contains('Internal order id: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'));
  });

  test('sheet copy says the conversation is already linked', () {
    expect(
      supportLinkedOrderCopy(orderNumber: 'OCB30688'),
      contains('linked to order OCB30688'),
    );
    expect(
      supportLinkedOrderCopy(),
      isNot(contains('Include your order id')),
    );
  });
}
