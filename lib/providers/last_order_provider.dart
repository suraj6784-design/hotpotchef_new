import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../services/reorder_service.dart';

final lastOrderProvider =
    NotifierProvider<LastOrderNotifier, Map<String, dynamic>?>(LastOrderNotifier.new);

class LastOrderNotifier extends Notifier<Map<String, dynamic>?> {
  final _supabase = Supabase.instance.client;

  @override
  Map<String, dynamic>? build() {
    fetchLastOrder();
    return null;
  }

  Future<void> fetchLastOrder() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        state = null;
        return;
      }

      List<dynamic> rows = const [];
      try {
        rows = await _supabase
            .from('orders')
            .select()
            .eq('customer_id', user.id)
            .order('created_at', ascending: false)
            .limit(30);
      } catch (_) {
        rows = await _supabase
            .from('orders')
            .select()
            .or('customer_id.eq.${user.id},user_id.eq.${user.id}')
            .order('created_at', ascending: false)
            .limit(30);
      }
      state = lastSuccessfulOrder(rows);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch last order');
    }
  }

  void clear() {
    state = null;
  }
}
