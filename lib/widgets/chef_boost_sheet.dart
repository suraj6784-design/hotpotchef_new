import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/helpers.dart';
import '../utils/network.dart';

Future<void> showChefBoostSheet(BuildContext context, Map<String, dynamic> meal) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: AppTheme.bottomSheetDecoration(isDark: isDark),
      child: ChefBoostSheet(meal: meal),
    ),
  );
}

class ChefBoostSheet extends StatefulWidget {
  const ChefBoostSheet({super.key, required this.meal});

  final Map<String, dynamic> meal;

  @override
  State<ChefBoostSheet> createState() => _ChefBoostSheetState();
}

class _ChefBoostSheetState extends State<ChefBoostSheet> {
  late final Razorpay _razorpay;
  bool _paying = false;
  String? _boostId;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _startPay() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'meal-boost',
        body: {
          'action': 'create',
          'meal_id': widget.meal['id']?.toString(),
        },
      ).withTimeout(NetworkTimeouts.payment);

      final data = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : <String, dynamic>{};
      if (response.status != 200 || data['success'] != true) {
        throw Exception(data['error']?.toString() ?? 'Could not start the boost payment.');
      }

      final key = dotenv.env['RAZORPAY_KEY_ID'] ?? '';
      if (key.isEmpty) throw Exception('Payment gateway configuration missing.');

      _boostId = data['boost_id']?.toString();
      _razorpay.open({
        'key': key,
        'amount': data['amount'] ?? kChefBoostPaise,
        'name': 'HotPotChef',
        'description': 'Boost ${widget.meal['title'] ?? 'this dish'} on Home',
        'order_id': data['order_id'],
        'retry': {'enabled': false, 'max_count': 0},
        'theme': {'color': '#F4511E'},
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef boost payment failed to start');
      if (!mounted) return;
      setState(() => _paying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(boostPaymentErrorMessage(e)), backgroundColor: Colors.orangeAccent),
      );
    }
  }

  Future<void> _onSuccess(PaymentSuccessResponse response) async {
    try {
      final confirm = await Supabase.instance.client.functions.invoke(
        'meal-boost',
        body: {
          'action': 'confirm',
          'boost_id': _boostId,
          'razorpay_order_id': response.orderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
        },
      ).withTimeout(NetworkTimeouts.payment);
      final data = confirm.data is Map ? Map<String, dynamic>.from(confirm.data as Map) : <String, dynamic>{};
      if (confirm.status != 200 || data['success'] != true) {
        throw Exception(data['error'] ?? 'Payment succeeded but the boost did not activate.');
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.meal['title'] ?? 'Dish'} is now a paid Home placement (paid promotion) until midnight.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef boost confirm failed');
      if (!mounted) return;
      setState(() => _paying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(checkoutErrorMessage(e)), backgroundColor: Colors.orangeAccent),
      );
    }
  }

  void _onError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _paying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(response.message?.toString().trim().isNotEmpty == true
            ? response.message!
            : 'Boost payment was cancelled. Nothing was charged.'),
        backgroundColor: Colors.orangeAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final until = formatAppTime(boostEndsAtLocalMidnight(DateTime.now()));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.hairlineOf(context),
                borderRadius: AppTheme.radiusXl,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Boost this dish today',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₹$kChefBoostRupees buys a paid Home placement (paid promotion) — this dish first on diner Home offers until $until. Charged to your kitchen — not taken from diner orders.',
            style: TextStyle(fontSize: 14, height: 1.4, color: isDark ? Colors.grey.shade400 : AppTheme.textMuted),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: _paying ? null : _startPay,
              child: Text(
                _paying ? 'Opening payment…' : 'Pay ₹$kChefBoostRupees to boost',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
