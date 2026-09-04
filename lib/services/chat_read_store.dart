import 'package:shared_preferences/shared_preferences.dart';

class ChatReadStore {
  ChatReadStore._();

  static String _key(String roomId) => 'chat_read_$roomId';

  static Future<void> markRead(String roomId) async {
    final id = roomId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(id), DateTime.now().toUtc().toIso8601String());
  }

  static Future<DateTime?> lastRead(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_key(roomId)) ?? '');
  }

  static Future<Map<String, DateTime>> lastReadByRoom(Iterable<String> roomIds) async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, DateTime>{};
    for (final roomId in roomIds) {
      final at = DateTime.tryParse(prefs.getString(_key(roomId)) ?? '');
      if (at != null) out[roomId] = at;
    }
    return out;
  }
}
