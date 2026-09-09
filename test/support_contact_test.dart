import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/support.dart';

void main() {
  test('ops public reply moves the ticket to pending customer unless already there', () {
    expect(shouldMarkPendingCustomerAfterOpsPublicReply('open'), isTrue);
    expect(shouldMarkPendingCustomerAfterOpsPublicReply('resolved'), isTrue);
    expect(shouldMarkPendingCustomerAfterOpsPublicReply('pending_customer'), isFalse);
  });

  test('ticket SLA copy uses a local clock, not an ISO timestamp', () {
    expect(
      formatTicketSlaDue('2026-06-09T20:10:47.565553+00:00'),
      isNot(contains('T20:10')),
    );
    expect(formatTicketSlaDue('2026-06-09T20:10:47.565553+00:00'), isNot(contains('+00:00')));
  });

  test('diner notice waits on pending_customer until the last message is seen', () {
    expect(
      dinerHasSupportReplyWaiting(status: 'pending_customer', lastMessageAt: 'a', lastSeenMessageAt: null),
      isTrue,
    );
    expect(
      dinerHasSupportReplyWaiting(status: 'pending_customer', lastMessageAt: 'a', lastSeenMessageAt: 'a'),
      isFalse,
    );
    expect(dinerHasSupportReplyWaiting(status: 'open', lastMessageAt: 'a'), isFalse);
    expect(
      supportRepliedNoticeCopy(publicId: 'TKT-AF743674'),
      'Support replied on TKT-AF743674.',
    );
  });

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

  test('supply request id is stable for a given time', () {
    expect(
      newSupplyRequestId(DateTime.utc(2026, 9, 5, 2, 13)),
      newSupplyRequestId(DateTime.utc(2026, 9, 5, 2, 13)),
    );
    expect(newSupplyRequestId(DateTime.utc(2026, 9, 5, 2, 13)), startsWith('SUP-'));
  });

  test('supply request message includes request, chef, item and qty', () {
    final message = supportSupplyRequestMessage(
      requestId: 'SUP-ABC123',
      chefName: 'New Chef 16',
      chefEmail: 'newchef16@test.com',
      chefPhone: '9876543210',
      chefUserId: 'chef-uuid',
      kitchenAddress: '2, Thergaon, Pimpri-Chinchwad - 411033',
      itemTitle: 'Eco-Friendly Meal Box (500ml)',
      itemSku: 'm1',
      quantity: 3,
      itemDescription: 'Pack of 50',
      unitPrice: 250,
    );

    expect(supportSupplyRequestSubject('SUP-ABC123'), 'HotPotChef supply request — SUP-ABC123');
    expect(message, contains('Request ID: SUP-ABC123'));
    expect(message, contains('Name: New Chef 16'));
    expect(message, contains('Email: newchef16@test.com'));
    expect(message, contains('Phone: 9876543210'));
    expect(message, contains('Chef ID: chef-uuid'));
    expect(message, contains('Kitchen: 2, Thergaon, Pimpri-Chinchwad - 411033'));
    expect(message, contains('Item: Eco-Friendly Meal Box (500ml)'));
    expect(message, contains('SKU: m1'));
    expect(message, contains('Quantity: 3'));
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
