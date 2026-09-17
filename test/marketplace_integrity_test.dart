import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/utils/legal_content.dart';

void main() {
  group('orderAllowsPartyChat', () {
    test('stays open during out for delivery but closes when delivered', () {
      expect(orderAllowsPartyChat('Out for Delivery'), isTrue);
      expect(orderAllowsPartyChat('Delivered'), isFalse);
      expect(orderAllowsPartyChat('Completed'), isFalse);
    });
  });

  group('orderAllowsPhoneCall', () {
    test('allows active fulfilment statuses only', () {
      expect(orderAllowsPhoneCall('Confirmed'), isTrue);
      expect(orderAllowsPhoneCall('Preparing'), isTrue);
      expect(orderAllowsPhoneCall('Ready for Pickup'), isTrue);
      expect(orderAllowsPhoneCall('Out for Delivery'), isTrue);
      expect(orderAllowsPhoneCall('Pending Chef Approval'), isFalse);
      expect(orderAllowsPhoneCall('Pending Payment'), isFalse);
      expect(orderAllowsPhoneCall('Delivered'), isFalse);
      expect(orderAllowsPhoneCall('Cancelled'), isFalse);
    });
  });

  group('messageSolicitsOffAppPayment', () {
    test('flags UPI / WhatsApp payment solicitations', () {
      expect(messageSolicitsOffAppPayment('Pay me on UPI next time'), isTrue);
      expect(messageSolicitsOffAppPayment('WhatsApp me for payment'), isTrue);
      expect(messageSolicitsOffAppPayment('send to my gpay'), isTrue);
      expect(messageSolicitsOffAppPayment('Running 10 min late — use the lobby'), isFalse);
      expect(messageSolicitsOffAppPayment('Thanks for ordering!'), isFalse);
    });
  });

  test('terms and FAQ cover marketplace integrity', () {
    final terms = legalDocumentFor(LegalDocumentType.terms);
    expect(
      terms.sections.any((s) => s.heading.toLowerCase().contains('marketplace integrity')),
      isTrue,
    );
    final faq = legalDocumentFor(LegalDocumentType.faq);
    expect(
      faq.sections.any((s) => s.heading.toLowerCase().contains('whatsapp') || s.body.toLowerCase().contains('whatsapp')),
      isTrue,
    );
  });
}
