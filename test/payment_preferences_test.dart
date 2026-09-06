import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/payment_preferences.dart';

void main() {
  test('normalizes payment preferences and labels', () {
    expect(normalizeCustomerPayMethod('UPI'), 'upi');
    expect(normalizeCustomerPayMethod('card'), 'card');
    expect(normalizeCustomerPayMethod('netbanking'), 'netbanking');
    expect(normalizeCustomerPayMethod('cash'), 'upi');
    expect(customerPayMethodLabel('card'), contains('card'));
    expect(customerPayMethodLabel('netbanking'), contains('banking'));
  });

  test('razorpay options enable UPI, card, and netbanking', () {
    final opts = razorpayMethodOptions('card');
    expect(opts['prefillMethod'], 'card');
    final methods = opts['method'] as Map;
    expect(methods['upi'], isTrue);
    expect(methods['card'], isTrue);
    expect(methods['netbanking'], isTrue);
  });
}
