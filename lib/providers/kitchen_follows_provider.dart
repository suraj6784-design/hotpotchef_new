// lib/providers/kitchen_follows_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/helpers.dart';

final kitchenFollowsProvider =
    NotifierProvider<KitchenFollowsNotifier, Set<String>>(KitchenFollowsNotifier.new);

class KitchenFollowsNotifier extends Notifier<Set<String>> {
  final _supabase = Supabase.instance.client;

  @override
  Set<String> build() {
    fetchFollows();
    return {};
  }

  Future<void> fetchFollows() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        state = {};
        return;
      }

      final res = await _supabase
          .from('kitchen_follows')
          .select('chef_id')
          .eq('customer_id', user.id);

      state = {
        for (final row in res)
          if ((row['chef_id']?.toString() ?? '').isNotEmpty) row['chef_id'].toString(),
      };
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch kitchen follows');
    }
  }

  Future<bool> toggleFollow(String chefId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    if (!canFollowKitchen(viewerId: user.id, chefId: chefId)) return false;

    final following = state.contains(chefId);
    final next = Set<String>.from(state);
    if (following) {
      next.remove(chefId);
    } else {
      next.add(chefId);
    }
    state = next;

    try {
      if (following) {
        await _supabase
            .from('kitchen_follows')
            .delete()
            .eq('customer_id', user.id)
            .eq('chef_id', chefId);
      } else {
        await _supabase.from('kitchen_follows').insert({
          'customer_id': user.id,
          'chef_id': chefId,
        });
      }
      return true;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to toggle kitchen follow');
      await fetchFollows();
      return false;
    }
  }

  void clear() {
    state = {};
  }
}
