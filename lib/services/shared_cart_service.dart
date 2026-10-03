// lib/services/shared_cart_service.dart

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../models/cart_state.dart';
import '../utils/helpers.dart';

String? dinerDisplayNameFromUser({
  String? name,
  String? email,
}) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isNotEmpty) return trimmed;
  final local = email?.split('@').first.trim() ?? '';
  if (local.isNotEmpty) return local;
  return null;
}

/// A group plate can be changed only by the diner who added it.
/// Older plates with no owner stay with the host.
bool sharedCartLineEditable(
  CartItemModel item, {
  required String? userId,
  required String? hostId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  final owner = item.addedByUserId?.trim() ?? '';
  if (owner.isNotEmpty) return owner == uid;
  final host = hostId?.trim() ?? '';
  return host.isNotEmpty && host == uid;
}

String groupPlateOwnerLabel(
  CartItemModel item, {
  required String? userId,
  String? hostId,
}) {
  final uid = userId?.trim() ?? '';
  final owner = item.addedByUserId?.trim() ?? '';
  final host = hostId?.trim() ?? '';
  if (uid.isNotEmpty && (owner == uid || (owner.isEmpty && host == uid))) return 'You';
  final name = item.addedByName?.trim() ?? '';
  if (name.isNotEmpty) return name;
  if (owner.isEmpty) return 'Host';
  return 'Teammate';
}

/// Keeps teammates' plates from the server and applies only this diner's edits.
List<CartItemModel> mergeSharedCartItems({
  required List<CartItemModel> remote,
  required List<CartItemModel> local,
  required String? userId,
  required String? hostId,
}) {
  bool owns(CartItemModel item) => sharedCartLineEditable(
        item,
        userId: userId,
        hostId: hostId,
      );

  final localOwn = local.where(owns).toList();
  final seen = <String>{};
  final merged = <CartItemModel>[];
  for (final item in remote) {
    if (owns(item)) {
      CartItemModel? replacement;
      for (final localItem in localOwn) {
        if (localItem.id == item.id) {
          replacement = localItem;
          break;
        }
      }
      if (replacement != null) {
        merged.add(replacement);
        seen.add(replacement.id);
      }
    } else {
      merged.add(item);
    }
  }
  for (final item in localOwn) {
    if (!seen.contains(item.id)) merged.add(item);
  }
  return merged;
}

class SharedCartException implements Exception {
  SharedCartException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SharedCartJoinResult {
  const SharedCartJoinResult({
    required this.roomCode,
    required this.placeKind,
    required this.added,
    required this.skipped,
  });

  final String roomCode;
  final String placeKind;
  final int added;
  final List<String> skipped;

  String get joinedMessage {
    final kind = groupPlaceKindLabel(placeKind);
    final extra = skipped.isEmpty ? '' : ' Skipped: ${skipped.join(', ')}.';
    if (added <= 0 && skipped.isNotEmpty) {
      return 'Joined $kind · $roomCode, but those plates could not be added.$extra';
    }
    return 'Joined $kind · $roomCode. Later adds stay in sync.$extra';
  }
}

class SharedCartRoom {
  const SharedCartRoom({
    required this.roomCode,
    required this.items,
    this.hostId,
    this.status,
    this.placeKind = 'friends',
    this.placeLabel,
    this.dropoffNote,
    this.timeSlot,
  });

  final String roomCode;
  final List<CartItemModel> items;
  final String? hostId;
  final String? status;
  final String placeKind;
  final String? placeLabel;
  final String? dropoffNote;
  final String? timeSlot;
}

class SharedCartService {
  final _supabase = Supabase.instance.client;

  /// Creates a new group ordering room with a secure random 6-character code
  Future<String> createSharedCart(
    List<CartItemModel> initialItems, {
    String placeKind = 'friends',
    String? placeLabel,
    String? dropoffNote,
    String? timeSlot,
    String? selectedDate,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final rnd = Random();
      final roomCode = 'GRP-${List.generate(6, (index) => chars[rnd.nextInt(chars.length)]).join()}';

      final jsonList = initialItems
          .map((item) {
            final owner = item.addedByUserId?.trim() ?? '';
            if (owner.isNotEmpty) return item;
            return item.copyWith(
              addedByUserId: user.id,
              addedByName: dinerDisplayNameFromUser(
                name: user.userMetadata?['name']?.toString() ?? user.userMetadata?['full_name']?.toString(),
                email: user.email,
              ),
            );
          })
          .map((i) => i.toJson())
          .toList();
      final kind = normalizeGroupPlaceKind(placeKind);

      final payload = <String, dynamic>{
        'room_code': roomCode,
        'host_id': user.id,
        'items': jsonList,
        'status': 'open',
        'place_kind': kind,
        'place_label': placeLabel?.trim().isEmpty == true ? null : placeLabel?.trim(),
        'dropoff_note': dropoffNote?.trim().isEmpty == true ? null : dropoffNote?.trim(),
        'time_slot': timeSlot?.trim().isEmpty == true ? null : timeSlot?.trim(),
        'selected_date': selectedDate?.trim().isEmpty == true ? null : selectedDate?.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      try {
        await _supabase.from('shared_carts').insert(payload);
      } on PostgrestException catch (e) {
        // Older schemas may miss society columns or status.
        if (e.code != 'PGRST204') rethrow;
        payload.remove('status');
        payload.remove('place_kind');
        payload.remove('place_label');
        payload.remove('dropoff_note');
        payload.remove('time_slot');
        payload.remove('selected_date');
        await _supabase.from('shared_carts').insert(payload);
      }

      try {
        await _supabase.rpc('join_shared_cart', params: {'p_room_code': roomCode});
      } catch (_) {}

      return roomCode;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to create shared cart room');
      if (kDebugMode) debugPrint('Create shared cart error: $e');
      rethrow;
    }
  }

  Future<SharedCartRoom> fetchSharedCartRoom(String roomCode) async {
    final code = roomCode.toUpperCase().trim();
    try {
      Map<String, dynamic>? response;
      try {
        response = await _supabase
            .from('shared_carts')
            .select('items, status, host_id, place_kind, place_label, dropoff_note, time_slot')
            .eq('room_code', code)
            .maybeSingle();
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204') rethrow;
        response = await _supabase
            .from('shared_carts')
            .select('items, status, host_id')
            .eq('room_code', code)
            .maybeSingle();
      }

      final status = response?['status']?.toString().toLowerCase().trim();
      if (status == 'ordered' || status == 'closed') {
        throw SharedCartException('This group already checked out. Ask the host for a new link.');
      }

      if (response == null) {
        throw SharedCartException('No open group lunch for that code.');
      }

      try {
        await _supabase.rpc('join_shared_cart', params: {'p_room_code': code});
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') {
          throw SharedCartException('Could not join this group. Ask the host to send a new link.');
        }
      }

      final items = <CartItemModel>[];
      if (response['items'] is List) {
        for (final e in response['items'] as List) {
          items.add(CartItemModel.fromJson(Map<String, dynamic>.from(e as Map)));
        }
      }

      return SharedCartRoom(
        roomCode: code,
        items: items,
        hostId: response['host_id']?.toString(),
        status: status,
        placeKind: normalizeGroupPlaceKind(response['place_kind']?.toString()),
        placeLabel: response['place_label']?.toString(),
        dropoffNote: response['dropoff_note']?.toString(),
        timeSlot: response['time_slot']?.toString(),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch shared cart');
      if (kDebugMode) debugPrint('Fetch shared cart error: $e');
      rethrow;
    }
  }

  /// Fetches items for an existing group session once
  Future<List<CartItemModel>> fetchSharedCart(String roomCode) async {
    final room = await fetchSharedCartRoom(roomCode);
    return room.items;
  }

  Future<String?> sharedCartHostId(String roomCode) async {
    try {
      final row = await _supabase
          .from('shared_carts')
          .select('host_id')
          .eq('room_code', roomCode.toUpperCase().trim())
          .maybeSingle();
      return row?['host_id']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Streams live updates for a shared cart room (enables multi-user real-time collaboration)
  Stream<List<CartItemModel>> streamSharedCart(String roomCode) {
    return _supabase
        .from('shared_carts')
        .stream(primaryKey: ['id'])
        .eq('room_code', roomCode.toUpperCase().trim())
        .map((data) {
          if (data.isEmpty) return <CartItemModel>[];
          final status = data.first['status']?.toString().toLowerCase().trim();
          if (status == 'ordered' || status == 'closed') return <CartItemModel>[];
          if (data.first['items'] is List) {
            final rawList = data.first['items'] as List;
            return rawList
                .map((e) => CartItemModel.fromJson(Map<String, dynamic>.from(e)))
                .toList();
          }
          return <CartItemModel>[];
        });
  }

  /// Updates items in the shared room, broadcasting changes to all participants.
  /// Only this diner's plates are replaced. Teammates' plates stay as stored.
  Future<void> updateSharedCart(
    String roomCode,
    List<CartItemModel> items, {
    String? hostId,
  }) async {
    try {
      final code = roomCode.toUpperCase().trim();
      final userId = _supabase.auth.currentUser?.id;
      var remote = items;
      var resolvedHost = hostId;
      try {
        final row = await _supabase
            .from('shared_carts')
            .select('items, host_id')
            .eq('room_code', code)
            .maybeSingle();
        resolvedHost ??= row?['host_id']?.toString();
        final raw = row?['items'];
        if (raw is List) {
          remote = raw
              .whereType<Map>()
              .map((e) => CartItemModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to read shared cart before update');
        return;
      }

      final merged = mergeSharedCartItems(
        remote: remote,
        local: items,
        userId: userId,
        hostId: resolvedHost,
      );
      final jsonList = merged.map((i) => i.toJson()).toList();

      await _supabase.from('shared_carts').update({
        'items': jsonList,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('room_code', code);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to update shared cart');
      if (kDebugMode) debugPrint('Update shared cart error: $e');
      rethrow;
    }
  }

  /// Closes a room after the paying member checks out so others cannot keep adding.
  Future<void> markSharedCartOrdered(String roomCode) async {
    final code = roomCode.toUpperCase().trim();
    if (code.isEmpty) return;
    try {
      await _supabase.from('shared_carts').update({
        'status': 'ordered',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('room_code', code);
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST204') {
        FirebaseCrashlytics.instance.recordError(e, StackTrace.current, reason: 'Failed to close shared cart');
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to close shared cart');
    }
  }
}
