import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/utils/payment_preferences.dart';

void main() {
  test('saved VPA must look like name@handle', () {
    expect(looksLikeVpa('name@upi'), isTrue);
    expect(looksLikeVpa('bad'), isFalse);
    expect(normalizeSavedVpa('Name@OKI'), 'name@oki');
  });

  test('Razorpay keeps card available when a VPA is saved', () {
    final upi = razorpayMethodOptions('upi', savedVpa: 'suraj@upi');
    expect(upi['vpa'], 'suraj@upi');
    expect(upi['prefillMethod'], 'upi');
    expect(upi['method']['upi'], isTrue);
    expect(upi['method']['card'], isTrue);

    final card = razorpayMethodOptions('card', savedVpa: 'suraj@upi');
    expect(card.containsKey('vpa'), isFalse);
    expect(card['prefillMethod'], 'card');
    expect(card['method']['card'], isTrue);
  });

  test('diner failure copy covers delay, double debit, and refund', () {
    expect(
      dinerPaymentFailureCopy('Payment cancelled'),
      contains('Nothing was confirmed'),
    );
    expect(dinerPaymentFailureCopy('already paid'), contains('two HotPotChef debits'));
    expect(dinerRefundMoneyCopy(refunded: true), contains('5–7 business days'));
    expect(
      dinerLateOrderCopy({
        'promised_at': DateTime(2026, 9, 17, 10).toIso8601String(),
        'status': 'On the way',
      }, now: DateTime(2026, 9, 17, 11)),
      contains('25 HotPot Coins'),
    );
  });
}
