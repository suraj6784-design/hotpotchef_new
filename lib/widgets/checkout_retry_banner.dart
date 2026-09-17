import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import '../utils/checkout_retry_queue.dart';
import '../utils/network.dart';

class CheckoutRetryBanner extends StatefulWidget {
  const CheckoutRetryBanner({super.key});

  @override
  State<CheckoutRetryBanner> createState() => _CheckoutRetryBannerState();
}

class _CheckoutRetryBannerState extends State<CheckoutRetryBanner> {
  CheckoutRetryJob? _job;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final job = await loadCheckoutRetryJob();
    if (!mounted) return;
    setState(() => _job = job);
  }

  Future<void> _retry() async {
    final job = _job;
    if (job == null || _busy) return;
    setState(() => _busy = true);
    try {
      final recover = await Supabase.instance.client.functions.invoke(
        'recover-payment',
        body: {
          ...job.body,
          'payment_id': job.paymentId,
          'razorpay_order_id': job.razorpayOrderId,
          'razorpay_signature': job.signature,
        },
      ).withTimeout(NetworkTimeouts.payment);
      final data = recover.data is Map ? Map<String, dynamic>.from(recover.data as Map) : null;
      if (data?['success'] == true) {
        await clearCheckoutRetryJob();
        if (!mounted) return;
        setState(() => _job = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded. Check Orders or Family member on Account.')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data?['error']?.toString() ?? 'Still waiting on the network. Try again.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(networkErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_job == null) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFFF3E0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: AppTheme.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'A payment finished on the phone but the order was not saved. Retry while you are online — you will not be charged again.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _retry,
              child: Text(_busy ? 'Retrying…' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
