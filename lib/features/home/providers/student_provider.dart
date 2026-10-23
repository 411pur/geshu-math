import 'package:web/web.dart' as web;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provides the student ID persisted in browser localStorage.
class StudentIdNotifier extends Notifier<String> {
  static const _key = 'geshu_math_student_id';

  @override
  String build() {
    try {
      final stored = web.window.localStorage.getItem(_key);
      if (stored != null && stored.isNotEmpty) return stored;
    } catch (_) {}
    return '';
  }

  void set(String id) {
    state = id;
    try { web.window.localStorage.setItem(_key, id); } catch (_) {}
  }
}

final studentIdProvider = NotifierProvider<StudentIdNotifier, String>(
  StudentIdNotifier.new,
);