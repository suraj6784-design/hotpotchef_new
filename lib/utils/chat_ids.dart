// lib/utils/chat_ids.dart
//
// Chat rooms are keyed by meal_id in `messages`. Cart line ids look like
// `${mealId}_${microseconds}` and must never be used as the room key, or the
// customer and chef land in different threads.

import 'dart:convert';

abstract final class ChatIds {
  static final _cartLineSuffix = RegExp(r'_\d{10,}$');

  /// True when [id] is a cart-line composite (`mealId` + timestamp), not a meal.
  static bool isCartLineId(String? id) {
    final value = id?.trim() ?? '';
    return value.isNotEmpty && _cartLineSuffix.hasMatch(value);
  }

  /// Drop the timestamp suffix from a cart-line id. Other ids are unchanged.
  static String stripCartLineSuffix(String? id) {
    final value = id?.trim() ?? '';
    if (value.isEmpty) return '';
    final match = _cartLineSuffix.firstMatch(value);
    if (match == null) return value;
    return value.substring(0, match.start);
  }

  /// Stable room id for a regular order / meal chat.
  ///
  /// Prefers `source_meal_id` / `mealId` / `meal_id`. Never returns a cart-line
  /// `${mealId}_ts`. Does not fall back to an order UUID.
  static String mealRoomId(Map<String, dynamic>? source) {
    if (source == null) return '';

    final preferred = _firstStableMealId([
      source['source_meal_id'],
      source['mealId'],
      source['meal_id'],
      source['sourceMealId'],
    ]);
    if (preferred.isNotEmpty) return preferred;

    final nested = _mealIdFromItems(source['items']);
    if (nested.isNotEmpty) return nested;

    final rawId = source['id']?.toString().trim() ?? '';
    if (isCartLineId(rawId)) return stripCartLineSuffix(rawId);
    return '';
  }

  /// Room id for a bulk catering request. Same prefix on customer and chef.
  static String bulkRequestRoomId(Object? requestId) {
    final raw = requestId?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    if (raw.startsWith('request_')) return raw;
    return 'request_$raw';
  }

  /// go_router location for `/chat/:mealId`.
  static String location(String roomId, {String? roomName}) {
    final id = roomId.trim();
    if (id.isEmpty) return '/chat/';
    final path = '/chat/${Uri.encodeComponent(id)}';
    if (roomName == null || roomName.trim().isEmpty) return path;
    return Uri(path: path, queryParameters: {'roomName': roomName.trim()}).toString();
  }

  static String _firstStableMealId(List<dynamic> candidates) {
    for (final candidate in candidates) {
      final raw = candidate?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      return isCartLineId(raw) ? stripCartLineSuffix(raw) : raw;
    }
    return '';
  }

  static String _mealIdFromItems(dynamic items) {
    List<dynamic>? list;
    if (items is List) {
      list = items;
    } else if (items is String && items.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(items);
        if (decoded is List) list = decoded;
      } catch (_) {
        return '';
      }
    }
    if (list == null || list.isEmpty) return '';
    for (final item in list) {
      if (item is Map) {
        final id = mealRoomId(Map<String, dynamic>.from(item));
        if (id.isNotEmpty) return id;
      }
    }
    return '';
  }
}
