import 'dart:convert';

/// Pure serialization boundary for local chat sessions.
class WrongQuestionSessionStore {
  static const version = 1;

  static List<Map<String, dynamic>> decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> || data['version'] != version) {
      throw const FormatException('Unknown history version');
    }
    final sessions = data['sessions'];
    if (sessions is! List) throw const FormatException('Invalid sessions');
    return sessions
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['id'] is String && item['state'] is Map)
        .toList();
  }

  static String encode(List<Map<String, dynamic>> sessions) =>
      jsonEncode({'version': version, 'sessions': sessions});
}
