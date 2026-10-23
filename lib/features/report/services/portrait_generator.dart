import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_provider.dart';
import '../../../core/network/sse_parser.dart';
import '../models/portrait_summary.dart';

/// 学生画像解读生成器：统计摘要 + 错误点摘要 → 一段 Markdown 画像。
///
/// 只把「总结层」数据送给模型（不送完整 200 条时间线），避免 token 膨胀；
/// 统计口径与页面上的图表一致。
class PortraitGenerator {
  PortraitGenerator._();

  static Future<String> generate(
    WidgetRef ref, {
    required PortraitSummary summary,
    required List<Map<String, dynamic>> trace,
    required String manualWeakPoints,
    required String name,
  }) async {
    final recent = trace.reversed.take(12).map((e) {
      final ts = e['ts'];
      final date = ts is num && ts > 0
          ? DateTime.fromMillisecondsSinceEpoch(ts.toInt())
          : null;
      return {
        'date': date == null ? '' : '${date.year}/${date.month}/${date.day}',
        'sub_topic': e['sub_topic'] ?? '',
        'error_type': e['error_type'] ?? '',
        'key_point': e['key_point'] ?? '',
        'question': e['question'] ?? '',
      };
    }).toList();

    final payload = json.encode({
      'student': {'name': name.trim().isEmpty ? '同学' : name.trim()},
      'statistics': {
        'total_wrong': summary.total,
        'pending': summary.pending,
        'mastered_rate': summary.masteredPercent,
        'week_new': summary.weekNew,
        'total_reviews': summary.reviewTotal,
        'streak_days': summary.streakDays,
        'active_days_30': summary.activeDays30,
      },
      'top_modules': {for (final e in summary.topModules) e.key: e.value},
      'weak_knowledge_points': {
        for (final e in summary.weakTags) e.key: e.value,
      },
      'error_types': {for (final e in summary.errorTypes) e.key: e.value},
      'weekly_new': [
        for (final w in summary.weekly) {'week': w.label, 'count': w.count},
      ],
      'recent_error_points': recent,
      'manual_weak_points': manualWeakPoints.trim(),
      'note': '统计来自错题本；掌握度为手动标记；未记录错因不能推断。',
    });

    final client = ref.read(aiApiClientProvider);
    var full = '';
    await for (final event in client.sendPortraitMessage(
      studentDataJson: payload,
    )) {
      if (event is MessageChunk) {
        full += event.answer;
      } else if (event is StreamError) {
        throw Exception(event.message);
      } else if (event is MessageEnd) {
        full = event.fullAnswer;
      }
    }
    return full.trim();
  }
}
