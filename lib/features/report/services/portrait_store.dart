import 'dart:convert';

import 'package:web/web.dart' as web;

/// 一份已生成的画像解读缓存（localStorage）。
class PortraitCache {
  const PortraitCache({
    required this.content,
    required this.generatedAt,
    required this.total,
  });

  final String content;
  final int generatedAt;

  /// 生成时错题本里的题目总数，用于提示「数据已变化」。
  final int total;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(generatedAt);
}

/// 画像解读的本地缓存：避免每次进页面都调用模型。
class PortraitStore {
  PortraitStore._();

  static const _key = 'geshu_math_portrait_ai';

  static PortraitCache? load() {
    try {
      final raw = web.window.localStorage.getItem(_key);
      if (raw == null || raw.isEmpty) return null;
      final j = json.decode(raw) as Map<String, dynamic>;
      final content = (j['content'] as String?) ?? '';
      if (content.trim().isEmpty) return null;
      return PortraitCache(
        content: content,
        generatedAt: (j['generated_at'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static void save({required String content, required int total}) {
    try {
      web.window.localStorage.setItem(
        _key,
        json.encode({
          'content': content,
          'generated_at': DateTime.now().millisecondsSinceEpoch,
          'total': total,
        }),
      );
    } catch (_) {}
  }

  static void clear() {
    try {
      web.window.localStorage.removeItem(_key);
    } catch (_) {}
  }
}
