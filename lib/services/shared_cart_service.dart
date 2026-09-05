// lib/services/shared_cart_service.dart

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../models/cart_state.dart';

class SharedCartService {
  final _supabase = Supabase.instance.client;

  /// Creates a new group ordering room with a secure random 6-character code
  Future<String> createSharedCart(List<CartItemModel> initialItems) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Generate a collision-resistant 6-character uppercase room code
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final rnd = Random();
      final roomCode = 'GRP-${List.generate(6, (index) => chars[rnd.nextInt(chars.length)]).join()}';

      final jsonList = initialItems.map((i) => i.toJson()).toList();

      final payload = {
        'room_code': roomCode,
        'host_id': user.id,
        'items': jsonList,
        'status': 'open',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      try {
        await _supabase.from('shared_carts').insert(payload);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204') rethrow;
        payload.remove('status');
        await _supabase.from('shared_carts').insert(payload);
      }

      return roomCode;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to create shared cart room');
      if (kDebugMode) debugPrint('Create shared cart error: $e');
      rethrow;
    }
  }

  /// Fetches items for an existing group session once
  Future<List<CartItemModel>> fetchSharedCart(String roomCode) async {
    try {
      Map<String, dynamic>? response;
      try {
        response = await _supabase
            .from('shared_carts')
            .select('items, status')
            .eq('room_code', roomCode.toUpperCase().trim())
            .maybeSingle();
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204') rethrow;
        response = await _supabase
            .from('shared_carts')
            .select('items')
            .eq('room_code', roomCode.toUpperCase().trim())
            .maybeSingle();
      }

      final status = response?['status']?.toString().toLowerCase().trim();
      if (status == 'ordered' || status == 'closed') {
        throw Exception('This group cart already checked out.');
      }

      if (response != null && response['items'] is List) {
        final rawList = response['items'] as List;
        return rawList
            .map((e) => CartItemModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      throw Exception('Group ordering room not found.');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch shared cart');
      if (kDebugMode) debugPrint('Fetch shared cart error: $e');
      rethrow;
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

  /// Updates items in the shared room, broadcasting changes to all participants
  Future<void> updateSharedCart(String roomCode, List<CartItemModel> items) async {
    try {
      final jsonList = items.map((i) => i.toJson()).toList();

      await _supabase.from('shared_carts').update({
        'items': jsonList,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('room_code', roomCode.toUpperCase().trim());
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