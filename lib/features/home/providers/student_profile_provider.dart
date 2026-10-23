import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 学生个人资料：名字 + 自定义头像（base64）。
class StudentProfile {
  final String name;
  final String avatarBase64; // data:image/png;base64,... 或空=默认头像
  const StudentProfile({this.name = '', this.avatarBase64 = ''});
  bool get hasAvatar => avatarBase64.isNotEmpty;
}

class StudentProfileNotifier extends Notifier<StudentProfile> {
  static const _key = 'geshu_math_student_profile';

  @override
  StudentProfile build() {
    try {
      final raw = web.window.localStorage.getItem(_key);
      if (raw != null && raw.isNotEmpty) {
        final j = json.decode(raw) as Map<String, dynamic>;
        return StudentProfile(
          name: (j['name'] as String?) ?? '',
          avatarBase64: (j['avatar'] as String?) ?? '',
        );
      }
    } catch (_) {}
    return const StudentProfile();
  }

  void setName(String name) => _save(state, name: name);
  void setAvatar(String avatarBase64) => _save(state, avatar: avatarBase64);

  void _save(StudentProfile cur, {String? name, String? avatar}) {
    final updated = StudentProfile(name: name ?? cur.name, avatarBase64: avatar ?? cur.avatarBase64);
    state = updated;
    try {
      web.window.localStorage.setItem(
        _key,
        json.encode({
          'name': updated.name,
          'avatar': updated.avatarBase64,
        }),
      );
    } catch (_) {}
  }
}

final studentProfileProvider = NotifierProvider<StudentProfileNotifier, StudentProfile>(
  StudentProfileNotifier.new,
);
