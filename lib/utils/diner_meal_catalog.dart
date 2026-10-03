import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'delivery_fee.dart';
import 'meal_catalog.dart';
import 'network.dart';

/// Columns a diner (including a guest) may read from `public.meals`.
///
/// `select *` is denied to `anon` while payout, transfer, FSSAI, and legacy
/// order columns stay revoked. PostgREST then fails the entire request, which
/// the home stream treated as a dropped connection.
const String kDinerMealCatalogColumns =
    'id,chef_id,title,price,is_veg,image_url,quantity,time_slot,is_hosting,status,'
    'category,service_type,description,chef_name,latitude,longitude,'
    'offer_type,discount_value,promo_code,accepts_hotpot_coins,average_rating,review_count,'
    'offer_valid_until,source_meal_id,created_at,health_tags,max_discount_cap,'
    'pickup_lat,pickup_lng,add_ons,promo_discount_type,promo_discount_value,boosted_until,'
    'is_hamper,is_society_night,society_label,is_shelf_item,shelf_kind,updated_at,'
    'calories_kcal,portion_weight_g,protein_g,carbs_g,fat_g,fiber_g,'
    'hosting_address,cuisine,prep_minutes,allergens,ingredients,video_url,'
    'availability_mode,dish_course,cook_minutes,serving_size,storage_hours,'
    'delivery_estimate_minutes,chef_tip,is_seasonal,allow_notify_when_available';

/// Never request these from the diner catalog. They are payout data, FSSAI
/// numbers, or another customer's order fields stored on older meal rows.
const List<String> kDinerMealCatalogPrivateColumns = [
  'driver_id',
  'delivery_address',
  'customer_name',
  'customer_phone',
  'special_instructions',
  'order_id',
  'embedding',
  'fssai_number',
  'platform_fee',
  'chef_payout_amount',
  'transfer_status',
  'razorpay_transfer_id',
  'razorpay_order_id',
];

Set<String> dinerMealCatalogColumnSet([String columns = kDinerMealCatalogColumns]) {
  return columns
      .split(',')
      .map((column) => column.trim())
      .where((column) => column.isNotEmpty)
      .toSet();
}

enum DinerHomeFeedPhase { loading, failed, ready }

/// A successful payload wins over a later error so a live catalog is not
/// replaced by the connection-error state. An empty list is a success.
DinerHomeFeedPhase dinerHomeFeedPhase({
  required bool loading,
  required Object? error,
  required bool hasPayload,
}) {
  if (hasPayload) return DinerHomeFeedPhase.ready;
  if (loading) return DinerHomeFeedPhase.loading;
  if (error != null) return DinerHomeFeedPhase.failed;
  return DinerHomeFeedPhase.loading;
}

bool dinerHomeFeedIsConnectionFailure(DinerHomeFeedPhase phase) =>
    phase == DinerHomeFeedPhase.failed;

Future<List<Map<String, dynamic>>> fetchDinerMealCatalog(
  SupabaseClient client, {
  int? limit,
  int? from,
  int? to,
  String? chefId,
}) async {
  var query = client
      .from('meals')
      .select(kDinerMealCatalogColumns)
      .eq('status', MealCatalog.availableStatus);
  final chef = chefId?.trim() ?? '';
  if (chef.isNotEmpty) {
    query = query.eq('chef_id', chef);
  }
  final ordered = query.order('created_at', ascending: false);
  final Future<dynamic> request;
  if (from != null && to != null) {
    request = ordered.range(from, to);
  } else {
    request = ordered.limit(limit ?? kHomeMealStreamLimit);
  }
  final rows = await request.withTimeout(NetworkTimeouts.standard);
  return List<Map<String, dynamic>>.from(rows as List);
}

/// Realtime refresh that refetches the guest-safe column list.
/// A failed fetch emits an error only until the first successful payload.
Stream<List<Map<String, dynamic>>> watchDinerMealCatalog(
  SupabaseClient client, {
  int limit = kHomeMealStreamLimit,
}) {
  late StreamController<List<Map<String, dynamic>>> controller;
  RealtimeChannel? channel;
  var closed = false;
  var pulling = false;
  var pullQueued = false;
  var hasPayload = false;

  Future<void> pull() async {
    if (closed) return;
    if (pulling) {
      pullQueued = true;
      return;
    }
    pulling = true;
    try {
      final rows = await fetchDinerMealCatalog(client, limit: limit);
      hasPayload = true;
      if (!closed) controller.add(rows);
    } catch (error, stack) {
      if (!hasPayload && !closed) controller.addError(error, stack);
    } finally {
      pulling = false;
      if (pullQueued && !closed) {
        pullQueued = false;
        await pull();
      }
    }
  }

  controller = StreamController<List<Map<String, dynamic>>>(
    onListen: () {
      final topic = 'diner-meals-${identityHashCode(controller)}';
      channel = client
          .channel(topic)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'meals',
            callback: (_) => unawaited(pull()),
          )
          .subscribe();
      unawaited(pull());
    },
    onCancel: () {
      closed = true;
      final active = channel;
      channel = null;
      if (active != null) {
        unawaited(active.unsubscribe());
        unawaited(client.removeChannel(active));
      }
    },
  );
  return controller.stream;
}
