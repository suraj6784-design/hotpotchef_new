// lib/providers/favorites_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

final favoritesProvider = NotifierProvider<FavoritesNotifier, Map<String, dynamic>>(FavoritesNotifier.new);

class FavoritesNotifier extends Notifier<Map<String, dynamic>> {
  final _supabase = Supabase.instance.client;

  @override
  Map<String, dynamic> build() {
    fetchFavorites();
    return {};
  }

  Future<void> fetchFavorites() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final res = await _supabase
          .from('user_favorites')
          .select('meal_id')
          .eq('user_id', user.id);

      final Map<String, dynamic> favs = {};
      for (var row in res) {
        final mealId = row['meal_id']?.toString();
        if (mealId != null) {
          favs[mealId] = true;
        }
      }
      state = favs;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch favorites');
    }
  }

  Future<void> toggleFavorite(String mealId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final isCurrentlyFav = state.containsKey(mealId);
      final newState = Map<String, dynamic>.from(state);
      if (isCurrentlyFav) {
        newState.remove(mealId);
      } else {
        newState[mealId] = true;
      }
      state = newState;

      if (isCurrentlyFav) {
        await _supabase.from('user_favorites').delete().eq('user_id', user.id).eq('meal_id', mealId);
      } else {
        await _supabase.from('user_favorites').insert({'user_id': user.id, 'meal_id': mealId});
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to toggle favorite');
      fetchFavorites();
    }
  }
  void clear() {
    state = {};
  }
}