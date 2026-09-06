import 'package:shared_preferences/shared_preferences.dart';

const kPreferredPaymentMethodKey = 'preferred_payment_method';

/// Customer checkout preference for Razorpay Standard Checkout.
/// HotPotChef never stores card/UPI/bank credentials — only this preference.
const kCustomerPayMethods = ['upi', 'card', 'netbanking'];

String normalizeCustomerPayMethod(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (kCustomerPayMethods.contains(value)) return value;
  return 'upi';
}

String customerPayMethodLabel(String? raw) {
  switch (normalizeCustomerPayMethod(raw)) {
    case 'card':
      return 'Credit / Debit card';
    case 'netbanking':
      return 'Net banking';
    case 'upi':
    default:
      return 'UPI';
  }
}

String customerPayMethodSubtitle(String? raw) {
  switch (normalizeCustomerPayMethod(raw)) {
    case 'card':
      return 'Cards via Razorpay at checkout';
    case 'netbanking':
      return 'Bank transfer via Razorpay at checkout';
    case 'upi':
    default:
      return 'UPI apps & QR via Razorpay at checkout';
  }
}

Future<String> loadPreferredPaymentMethod() async {
  final prefs = await SharedPreferences.getInstance();
  return normalizeCustomerPayMethod(prefs.getString(kPreferredPaymentMethodKey));
}

Future<void> savePreferredPaymentMethod(String method) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kPreferredPaymentMethodKey, normalizeCustomerPayMethod(method));
}

/// Razorpay checkout `prefill.method` + enabled instrument flags.
Map<String, dynamic> razorpayMethodOptions(String? preferred) {
  final method = normalizeCustomerPayMethod(preferred);
  return {
    'prefillMethod': method,
    'method': {
      'upi': true,
      'card': true,
      'netbanking': true,
      'wallet': false,
      'emi': false,
      'paylater': false,
    },
  };
}
