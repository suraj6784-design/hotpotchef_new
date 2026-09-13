import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Browse → pay → delivered funnel. Failures never break checkout or feed.
class AppAnalytics {
  AppAnalytics._();

  static Future<void> logViewMeal({
    required String mealId,
    String? chefId,
    String? title,
  }) {
    return _log('view_item', {
      'item_id': mealId,
      if ((chefId ?? '').isNotEmpty) 'chef_id': chefId!,
      if ((title ?? '').isNotEmpty) 'item_name': title!,
    });
  }

  static Future<void> logAddToCart({
    required String mealId,
    String? chefId,
    int quantity = 1,
  }) {
    return _log('add_to_cart', {
      'item_id': mealId,
      if ((chefId ?? '').isNotEmpty) 'chef_id': chefId!,
      'quantity': quantity,
    });
  }

  static Future<void> logBeginCheckout({
    required int itemCount,
    required double value,
  }) {
    return _log('begin_checkout', {
      'items': itemCount,
      'value': value,
      'currency': 'INR',
    });
  }

  static Future<void> logPurchase({
    String? orderId,
    required double value,
    String? paymentId,
  }) {
    return _log('purchase', {
      if ((orderId ?? '').isNotEmpty) 'transaction_id': orderId!,
      'value': value,
      'currency': 'INR',
      if ((paymentId ?? '').isNotEmpty) 'payment_id': paymentId!,
    });
  }

  static Future<void> logOrderDelivered({required String orderId}) {
    return _log('order_delivered', {'transaction_id': orderId});
  }

  static Future<void> _log(String name, Map<String, Object> params) async {
    try {
      await FirebaseAnalytics.instance.logEvent(name: name, parameters: params);
    } catch (e, st) {
      if (kDebugMode) debugPrint('AppAnalytics $name skipped: $e');
      try {
        FirebaseCrashlytics.instance.recordError(e, st, reason: 'Analytics $name failed');
      } catch (_) {}
    }
  }
}
