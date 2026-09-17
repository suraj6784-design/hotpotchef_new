import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/utils/payment_preferences.dart';

void main() {
  test('saved VPA must look like name@handle', () {
    expect(looksLikeVpa('name@upi'), isTrue);
    expect(looksLikeVpa('bad'), isFalse);
    expect(normalizeSavedVpa('Name@OKI'), 'name@oki');
  });

  test('Razorpay shortens to UPI when a VPA is saved', () {
    final opts = razorpayMethodOptions('upi', savedVpa: 'suraj@upi');
    expect(opts['vpa'], 'suraj@upi');
    expect(opts['method']['upi'], isTrue);
    expect(opts['method']['card'], isFalse);
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
