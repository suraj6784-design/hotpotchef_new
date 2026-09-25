import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/delivery_fee.dart';
import '../utils/network.dart';

/// Diner reads of `meals`. Always uses the granted catalog columns, never `select *`.
class MealCatalogRepository {
  MealCatalogRepository([SupabaseClient? client]) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> availableMeals({
    String? chefId,
    int limit = kHomeMealStreamLimit,
  }) {
    return _available(
      chefId: chefId,
      apply: (query) => query.limit(limit),
    );
  }

  Future<List<Map<String, dynamic>>> availableMealsPage({
    required int from,
    required int to,
  }) {
    return _available(apply: (query) => query.range(from, to));
  }

  Future<Map<String, dynamic>?> mealById(String mealId) async {
    if (mealId.isEmpty) return null;
    try {
      final row = await _client
          .from('meals')
          .select(kHomeMealCatalogSelect)
          .eq('id', mealId)
          .maybeSingle()
          .withTimeout(NetworkTimeouts.standard);
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (_) {
      final row = await _client
          .from('meals')
          .select(kHomeMealCatalogSelectMinimal)
          .eq('id', mealId)
          .maybeSingle()
          .withTimeout(NetworkTimeouts.standard);
      return row == null ? null : Map<String, dynamic>.from(row);
    }
  }

  Future<List<Map<String, dynamic>>> mealsLikeCategory(String category, {int limit = 5}) async {
    final pattern = '%$category%';
    try {
      final rows = await _client
          .from('meals')
          .select(kHomeMealCatalogSelect)
          .ilike('category', pattern)
          .limit(limit)
          .withTimeout(NetworkTimeouts.standard);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      final rows = await _client
          .from('meals')
          .select(kHomeMealCatalogSelectMinimal)
          .ilike('category', pattern)
          .limit(limit)
          .withTimeout(NetworkTimeouts.standard);
      return List<Map<String, dynamic>>.from(rows);
    }
  }

  Future<dynamic> addOnsForMeal(String mealId) async {
    final row = await _client
        .from('meals')
        .select('add_ons')
        .eq('id', mealId)
        .maybeSingle()
        .withTimeout(NetworkTimeouts.short);
    return row?['add_ons'];
  }

  Future<List<Map<String, dynamic>>> _available({
    String? chefId,
    required PostgrestTransformBuilder<PostgrestList> Function(
      PostgrestTransformBuilder<PostgrestList> query,
    ) apply,
  }) async {
    try {
      return await _run(kHomeMealCatalogSelect, chefId: chefId, apply: apply);
    } catch (_) {
      return _run(kHomeMealCatalogSelectMinimal, chefId: chefId, apply: apply);
    }
  }

  Future<List<Map<String, dynamic>>> _run(
    String columns, {
    String? chefId,
    required PostgrestTransformBuilder<PostgrestList> Function(
      PostgrestTransformBuilder<PostgrestList> query,
    ) apply,
  }) async {
    var query = _client.from('meals').select(columns).eq('status', 'Available');
    if (chefId != null && chefId.isNotEmpty) {
      query = query.eq('chef_id', chefId);
    }
    final rows = await apply(query.order('created_at', ascending: false)).withTimeout(NetworkTimeouts.standard);
    return List<Map<String, dynamic>>.from(rows);
  }
}
