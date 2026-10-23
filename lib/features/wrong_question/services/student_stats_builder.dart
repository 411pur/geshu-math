import 'dart:convert';
import '../../../domain/entities/wrong_question_entity.dart';

/// 学生错题统计构建器（快速版个性化）：
/// 从本地错题本计算统计性信息，打包成 JSON 字符串传给错题指导工作流，
/// 让 AI 基于学生的错题概况给出个性化讲解。
/// 只统计数量/分布，不发送具体历史题目，兼顾隐私与速度。
class StudentStatsBuilder {
  /// 构建统计 JSON（返回 null 表示没有错题数据，不注入个性化）。
  static String? build(List<WrongQuestion> all) {
    if (all.isEmpty) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final weekAgo = now - 7 * 86400000;

    // 模块分布（topic）
    final moduleCount = <String, int>{};
    // 掌握度分布 0/1/2
    var mastery0 = 0, mastery2 = 0;
    // 复习次数累计
    var totalReviews = 0;
    // 本周新增
    var weekNew = 0;
    // 薄弱知识点（tags/knowledge 中高频出现，简单统计）
    final weakCounter = <String, int>{};

    for (final w in all) {
      final topic = (w.topic ?? '').trim();
      if (topic.isNotEmpty) {
        moduleCount[topic] = (moduleCount[topic] ?? 0) + 1;
      }
      switch (w.mastery) {
        case 0: mastery0++; break;
        case 2: mastery2++; break;
      }
      totalReviews += w.reviewCount;
      if (w.createdAt >= weekAgo) weekNew++;

      // 统计 tags（作为薄弱/常见点）
      if (w.tagsJson != null && w.tagsJson!.isNotEmpty) {
        try {
          final tags = json.decode(w.tagsJson!) as List<dynamic>;
          for (final t in tags) {
            final s = t.toString().trim();
            if (s.isNotEmpty) weakCounter[s] = (weakCounter[s] ?? 0) + 1;
          }
        } catch (_) {}
      }
    }

    // 掌握率 = 已掌握占比
    final total = all.length;
    final masteredRate = total > 0 ? (mastery2 / total * 100).round() : 0;
    final unmasteredRate = total > 0 ? (mastery0 / total * 100).round() : 0;

    // 高频薄弱点（top3）
    final topWeak = weakCounter.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topWeakTags = topWeak.take(3).map((e) => e.key).toList();

    // 高频模块（top3）
    final topModules = moduleCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final stats = <String, dynamic>{
      'total_wrong_questions': total,
      'week_new': weekNew,
      'mastered_rate': masteredRate,
      'unmastered_rate': unmasteredRate,
      'total_reviews': totalReviews,
      'top_modules': topModules.take(3).map((e) => e.key).toList(),
      'weak_tags': topWeakTags,
    };

    return json.encode(stats);
  }
}