import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers.dart';

/// Columns Postgres stores with TOAST. An `UPDATE` that does not touch them
/// (accept only writes `status`) omits them from the realtime record. The
/// chef orders stream used to replace the whole row, so the card lost `items`
/// and fell back to "Requested ASAP" while `promised_at` still counted down.
const chefOrderToastColumns = <String>{
  'items',
  'cart_items',
  'special_instructions',
  'delivery_address',
};

bool chefOrderToastValueMissing(dynamic value) => value == null;

/// Overlay [incoming] onto [previous], keeping toasted columns the update dropped.
Map<String, dynamic> mergeChefOrderRealtimeRow(
  Map<String, dynamic>? previous,
  Map<String, dynamic> incoming,
) {
  if (previous == null || previous.isEmpty) {
    return Map<String, dynamic>.from(incoming);
  }
  final merged = Map<String, dynamic>.from(previous);
  for (final entry in incoming.entries) {
    if (chefOrderToastColumns.contains(entry.key) &&
        chefOrderToastValueMissing(entry.value)) {
      continue;
    }
    merged[entry.key] = entry.value;
  }
  return merged;
}

/// Apply one realtime orders change without dropping the diner's slot payload.
List<Map<String, dynamic>> applyChefOrderRealtimeEvent(
  List<Map<String, dynamic>> current, {
  required String event,
  Map<String, dynamic>? record,
}) {
  final rows = [for (final row in current) Map<String, dynamic>.from(row)];
  final incoming = record == null
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(record);
  final id = incoming['id']?.toString() ?? '';
  if (event == 'delete') {
    if (id.isEmpty) return rows;
    rows.removeWhere((row) => row['id']?.toString() == id);
    return rows;
  }
  if (id.isEmpty) return rows;
  final index = rows.indexWhere((row) => row['id']?.toString() == id);
  final merged = mergeChefOrderRealtimeRow(
    index >= 0 ? rows[index] : null,
    incoming,
  );
  if (index >= 0) {
    rows[index] = merged;
  } else {
    rows.add(merged);
  }
  return rows;
}

/// Chef orders feed. Initial select has `items`; later status updates merge
/// onto that row so a dropped TOAST column cannot blank the requested slot.
Stream<List<Map<String, dynamic>>> watchChefOrders(
  SupabaseClient client,
  String chefId,
) {
  final controller = StreamController<List<Map<String, dynamic>>>();
  var rows = <Map<String, dynamic>>[];
  final pending = <void Function()>[];
  var ready = false;
  RealtimeChannel? channel;

  void emit() {
    if (controller.isClosed) return;
    controller.add([for (final row in rows) chefFacingOrderRow(row)]);
  }

  void applyPayload(PostgresChangePayload payload) {
    final isDelete = payload.eventType == PostgresChangeEvent.delete;
    final record = isDelete ? payload.oldRecord : payload.newRecord;
    final event = isDelete
        ? 'delete'
        : payload.eventType == PostgresChangeEvent.insert
        ? 'insert'
        : 'update';
    rows = applyChefOrderRealtimeEvent(rows, event: event, record: record);
    emit();
  }

  controller
    ..onListen = () {
      channel = client
          .channel('public:orders:chef:$chefId:${identityHashCode(controller)}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'chef_id',
              value: chefId,
            ),
            callback: (payload) {
              if (!ready) {
                pending.add(() => applyPayload(payload));
                return;
              }
              applyPayload(payload);
            },
          )
          .subscribe();

      unawaited(() async {
        try {
          final data = await client
              .from('orders')
              .select()
              .eq('chef_id', chefId);
          if (controller.isClosed) return;
          final loaded = <Map<String, dynamic>>[];
          for (final raw in data as List) {
            if (raw is Map) loaded.add(Map<String, dynamic>.from(raw));
          }
          rows = loaded;
          ready = true;
          for (final job in pending) {
            job();
          }
          pending.clear();
          emit();
        } catch (error, stackTrace) {
          ready = true;
          pending.clear();
          if (!controller.isClosed) controller.addError(error, stackTrace);
        }
      }());
    }
    ..onCancel = () {
      ready = false;
      pending.clear();
      final active = channel;
      channel = null;
      if (active != null) unawaited(active.unsubscribe());
    };
  return controller.stream;
}
