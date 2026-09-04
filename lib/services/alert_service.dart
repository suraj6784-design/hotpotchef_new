import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../main.dart';
import '../models/app_role.dart';
import '../services/auth_session.dart';
import '../utils/app_router.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../utils/notification_copy.dart';

/// Tracks which chat screen is open so we do not snackbar the conversation you are already in.
class ChatAlertScope {
  static String? activeMealId;
}

class AlertService {
  AlertService._();

  static final _supabase = Supabase.instance.client;
  static RealtimeChannel? _channel;
  static final Set<String> _shown = <String>{};
  static AppRole _role = AppRole.customer;

  static Future<void> start() async {
    await stop();
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    _role = await AuthSession.resolveRole();

    _channel = _supabase
        .channel('in-app-alerts-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chef_id',
            value: uid,
          ),
          callback: (payload) => _onOrderRow(payload.newRecord, previous: null, isInsert: true),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chef_id',
            value: uid,
          ),
          callback: (payload) => _onOrderRow(
            payload.newRecord,
            previous: payload.oldRecord,
            isInsert: false,
          ),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: uid,
          ),
          callback: (payload) => _onOrderRow(
            payload.newRecord,
            previous: payload.oldRecord,
            isInsert: false,
          ),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) => _onChatRow(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'customer_requests',
          callback: (payload) => _onLeadRow(payload.newRecord, previous: null, isInsert: true),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'customer_requests',
          callback: (payload) => _onLeadRow(
            payload.newRecord,
            previous: payload.oldRecord,
            isInsert: false,
          ),
        );

    _channel!.subscribe();
  }

  static Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _supabase.removeChannel(channel);
    }
  }

  static void notifyOrder({required String orderId, required String type}) {
    unawaited(_invoke({
      'table': 'orders',
      'type': type,
      'record': {'id': orderId},
    }));
  }

  static void notifyChat({required String messageId}) {
    unawaited(_invoke({
      'table': 'messages',
      'type': 'INSERT',
      'record': {'id': messageId},
    }));
  }

  static Future<void> _invoke(Map<String, dynamic> body) async {
    try {
      await _supabase.functions
          .invoke('send-push-notification', body: body)
          .withTimeout(NetworkTimeouts.short);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Alert invoke failed');
    }
  }

  static void _onOrderRow(
    Map<String, dynamic> row, {
    Map<String, dynamic>? previous,
    required bool isInsert,
  }) {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    final copy = orderAlertCopy(
      status: row['status']?.toString() ?? '',
      isInsert: isInsert,
      previousStatus: previous?['status']?.toString(),
      mealTitle: mealTitleFromItems(row['items']),
    );
    if (copy == null) return;

    final isChef = row['chef_id']?.toString() == uid;
    final isCustomer = row['customer_id']?.toString() == uid;
    if (copy.notifyChef && isChef) {
      _show('${row['id']}-${row['status']}', copy.title, copy.body);
    } else if (copy.notifyCustomer && isCustomer) {
      _show('${row['id']}-${row['status']}', copy.title, copy.body);
    }
  }

  static void _onLeadRow(
    Map<String, dynamic> row, {
    Map<String, dynamic>? previous,
    required bool isInsert,
  }) {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    final copy = leadAlertCopy(
      status: row['status']?.toString() ?? '',
      isInsert: isInsert,
      previousStatus: previous?['status']?.toString(),
      title: row['title']?.toString() ?? 'Catering lead',
    );
    if (copy == null) return;

    final isCustomer = row['customer_id']?.toString() == uid;
    final isClaimedChef = row['accepted_chef_id']?.toString() == uid;
    final shouldShow = (copy.notifyAllChefs && _role == AppRole.chef && !isCustomer) ||
        (copy.notifyClaimedChef && isClaimedChef) ||
        (copy.notifyCustomer && isCustomer);
    if (!shouldShow) return;

    _show(
      'lead-${row['id']}-${row['status']}',
      copy.title,
      copy.body,
    );
  }

  static void _onChatRow(Map<String, dynamic> row) {
    unawaited(_handleChatRow(row));
  }

  static Future<Set<String>?> _membersForRoom(String roomId) async {
    try {
      final order = await _supabase
          .from('orders')
          .select('customer_id, user_id, chef_id, driver_id, delivery_partner_id')
          .eq('id', roomId)
          .maybeSingle();
      if (order != null) return orderChatMemberIds(order);

      final request = await _supabase
          .from('customer_requests')
          .select('customer_id, accepted_chef_id')
          .eq('id', roomId)
          .maybeSingle();
      if (request != null) {
        return {
          if ((request['customer_id']?.toString() ?? '').isNotEmpty) request['customer_id'].toString(),
          if ((request['accepted_chef_id']?.toString() ?? '').isNotEmpty) request['accepted_chef_id'].toString(),
        };
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chat room member lookup failed');
    }
    return null;
  }

  static Future<void> _handleChatRow(Map<String, dynamic> row) async {
    final uid = _supabase.auth.currentUser?.id;
    final sender = row['sender_id']?.toString();
    final mealId = row['meal_id']?.toString();
    if (uid == null || sender == null || sender == uid) return;
    if (mealId != null && ChatAlertScope.activeMealId == mealId) return;

    final path = _currentPath();
    if (mealId != null && path == '/chat/$mealId') return;

    Set<String>? members;
    if (mealId != null && mealId.isNotEmpty) {
      members = await _membersForRoom(mealId);
    }
    if (!shouldNotifyChatMember(myId: uid, senderId: sender, memberIds: members)) return;

    _show(
      'msg-${row['id']}',
      members != null && mealId != null ? orderGroupAlertTitle(mealId) : 'New message',
      chatPreview(row['content']?.toString()),
    );
  }

  static String? _currentPath() {
    try {
      return AppRouter.router.state.uri.path;
    } catch (_) {
      return null;
    }
  }

  static void showBanner(String id, String title, String body) {
    _show(id, title, body);
  }

  static void _show(String id, String title, String body) {
    if (!_shown.add(id)) return;
    Future<void>.delayed(const Duration(seconds: 12), () => _shown.remove(id));

    final messenger = globalMessengerKey.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(body.isEmpty ? title : '$title — $body'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
