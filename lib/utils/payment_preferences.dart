import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kPreferredPaymentMethodKey = 'preferred_payment_method';
const kSavedVpaKey = 'saved_upi_vpa';

/// Preferred Razorpay instrument. Card PANs are never stored.
const kCustomerPayMethods = ['upi', 'card', 'netbanking'];

const _securePay = FlutterSecureStorage();

bool looksLikeVpa(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (value.length < 5 || value.length > 50) return false;
  return RegExp(r'^[a-z0-9.\-_]{2,}@[a-z]{2,}$').hasMatch(value);
}

String? normalizeSavedVpa(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  return looksLikeVpa(value) ? value : null;
}

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
      return 'Saved VPA if stored, otherwise UPI apps & QR';
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

Future<String?> loadSavedVpa() async {
  try {
    return normalizeSavedVpa(await _securePay.read(key: kSavedVpaKey));
  } catch (_) {
    return null;
  }
}

Future<void> saveSavedVpa(String? vpa) async {
  final normalized = normalizeSavedVpa(vpa);
  if (normalized == null) {
    await _securePay.delete(key: kSavedVpaKey);
    return;
  }
  await _securePay.write(key: kSavedVpaKey, value: normalized);
}

Future<bool> unlockSavedPayInstrument({String reason = 'Confirm it is you to pay faster'}) async {
  final auth = LocalAuthentication();
  try {
    final supported = await auth.isDeviceSupported();
    if (!supported) return true;
    return await auth.authenticate(
      localizedReason: reason,
      biometricOnly: false,
      persistAcrossBackgrounding: true,
    );
  } catch (_) {
    return true;
  }
}

/// Razorpay checkout `prefill.method` + enabled instrument flags.
/// UPI, card, and netbanking stay on; wallets/EMI/paylater stay off (no COD).
Map<String, dynamic> razorpayMethodOptions(String? preferred, {String? savedVpa}) {
  final method = normalizeCustomerPayMethod(preferred);
  final vpa = method == 'upi' ? normalizeSavedVpa(savedVpa) : null;
  return {
    'prefillMethod': method,
    if (vpa != null) 'vpa': vpa,
    'method': {
      'upi': true,
      'card': true,
      'netbanking': true,
      'wallet': false,
      'emi': false,
      'paylater': false,
    },
    'displayHide': const [
      {'method': 'wallet'},
      {'method': 'emi'},
      {'method': 'paylater'},
    ],
  };
}

bool razorpayIsTestKey(String keyId) => keyId.trim().startsWith('rzp_test_');
