import 'package:shared_preferences/shared_preferences.dart';

class TicketReplySeenStore {
  TicketReplySeenStore._();

  static String _key(String ticketId) => 'ticket_reply_seen_$ticketId';

  static Future<void> markSeen(String ticketId, String? lastMessageAt) async {
    final id = ticketId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(id), (lastMessageAt ?? '').trim());
  }

  static Future<String?> lastSeen(String ticketId) async {
    final id = ticketId.trim();
    if (id.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(id));
  }

  static Future<Map<String, String>> lastSeenByTicket(Iterable<String> ticketIds) async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, String>{};
    for (final ticketId in ticketIds) {
      final id = ticketId.trim();
      if (id.isEmpty) continue;
      final seen = prefs.getString(_key(id));
      if (seen != null) out[id] = seen;
    }
    return out;
  }
}
