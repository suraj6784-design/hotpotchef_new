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

      await _supabase.from('shared_carts').insert({
        'room_code': roomCode,
        'host_id': user.id,
        'items': jsonList,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

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
      final response = await _supabase
          .from('shared_carts')
          .select('items')
          .eq('room_code', roomCode.toUpperCase().trim())
          .maybeSingle();

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
          if (data.isNotEmpty && data.first['items'] is List) {
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
}