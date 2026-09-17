import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const kCheckoutRetryQueueKey = 'checkout_retry_payment';

class CheckoutRetryJob {
  const CheckoutRetryJob({
    required this.paymentId,
    this.razorpayOrderId,
    this.signature,
    this.body = const {},
  });

  final String paymentId;
  final String? razorpayOrderId;
  final String? signature;
  final Map<String, dynamic> body;

  Map<String, dynamic> toJson() => {
        'payment_id': paymentId,
        'razorpay_order_id': razorpayOrderId,
        'razorpay_signature': signature,
        'body': body,
      };

  factory CheckoutRetryJob.fromJson(Map<String, dynamic> json) {
    final nested = json['body'];
    return CheckoutRetryJob(
      paymentId: json['payment_id']?.toString() ?? '',
      razorpayOrderId: json['razorpay_order_id']?.toString(),
      signature: json['razorpay_signature']?.toString(),
      body: nested is Map ? Map<String, dynamic>.from(nested) : Map<String, dynamic>.from(json),
    );
  }

  bool get isValid => paymentId.isNotEmpty;
}

Future<void> saveCheckoutRetryJob(CheckoutRetryJob job) async {
  if (!job.isValid) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kCheckoutRetryQueueKey, jsonEncode(job.toJson()));
}

Future<CheckoutRetryJob?> loadCheckoutRetryJob() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kCheckoutRetryQueueKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final job = CheckoutRetryJob.fromJson(Map<String, dynamic>.from(decoded));
    return job.isValid ? job : null;
  } catch (_) {
    return null;
  }
}

Future<void> clearCheckoutRetryJob() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kCheckoutRetryQueueKey);
}
