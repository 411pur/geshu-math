import '../../../domain/entities/wrong_question_entity.dart';
import 'wrong_question_analytics.dart';

/// 学生画像的纯统计层（无 Flutter 依赖，可在 VM 单测）。
///
/// 与 [WrongQuestionAnalytics] 的分工：
/// - 后者回答「某段时间内错题怎么分布」，供学习报告按 7/30/90 天切换；
/// - 本类回答「这个学生长期是什么样」，固定看全量错题，额外算学习节奏
///   （周新增、连续学习天数、近 30 天活跃天数）与累计复习次数。
class PortraitSummary {
  const PortraitSummary({
    required this.now,
    required this.total,
    required this.pending,
    required this.masteredPercent,
    required this.weekNew,
    required this.reviewTotal,
    required this.streakDays,
    required this.activeDays30,
    required this.topModules,
    required this.weakTags,
    required this.errorTypes,
    required this.weekly,
  });

  final DateTime now;
  final int total;
  final int pending;
  final int masteredPercent;
  final int weekNew;
  final int reviewTotal;
  final int streakDays;
  final int activeDays30;

  /// 按错题数降序的模块分布（最多 5 项）。
  final List<MapEntry<String, int>> topModules;

  /// 仅统计未掌握/复习中的错题，按出现次数降序（最多 8 项）。
  final List<MapEntry<String, int>> weakTags;

  /// 结构化错因分布，按次数降序（最多 5 项，可能含「未记录」）。
  final List<MapEntry<String, int>> errorTypes;

  /// 近 8 周每周新增错题，按时间从早到晚。
  final List<PortraitWeek> weekly;

  bool get hasData => total > 0;

  /// 一句可用于标题下的概况描述。
  String get headline {
    if (total == 0) return '还没有错题记录';
    final parts = <String>['已收录 $total 道错题', '掌握率 $masteredPercent%'];
    if (weekNew > 0) parts.add('本周新增 $weekNew 道');
    return parts.join(' · ');
  }

  factory PortraitSummary.from(
    List<WrongQuestion> source, {
    required DateTime now,
  }) {
    final analytics = WrongQuestionAnalytics(source, now: now);
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final weekStart = today.subtract(const Duration(days: 6));

    var weekNew = 0;
    var reviewTotal = 0;
    final activeDays = <int>{};
    for (final q in source) {
      reviewTotal += q.reviewCount;
      final day = _dayOf(q.createdAt);
      if (!day.isBefore(weekStart) && day.isBefore(tomorrow)) {
        weekNew++;
      }
      final diff = today.difference(day).inDays;
      if (diff >= 0 && diff < 30) activeDays.add(diff);
    }

    // 连续学习天数：今天还没记录时从昨天往前数，避免早上打开就显示 0。
    final createdDays = <int>{
      for (final q in source) today.difference(_dayOf(q.createdAt)).inDays,
    };
    var streak = 0;
    var cursor = createdDays.contains(0) ? 0 : 1;
    while (createdDays.contains(cursor) && streak < 365) {
      streak++;
      cursor++;
    }

    final weekly = List.generate(8, (i) {
      final start = today.subtract(Duration(days: 7 * (7 - i)));
      final end = start.add(const Duration(days: 7));
      final count = source.where((q) {
        final created = q.createdAt;
        return created >= start.millisecondsSinceEpoch &&
            created < end.millisecondsSinceEpoch &&
            created < tomorrow.millisecondsSinceEpoch;
      }).length;
      return PortraitWeek(start: start, count: count);
    });

    return PortraitSummary(
      now: now,
      total: analytics.total,
      pending: analytics.pending,
      masteredPercent: analytics.masteredPercent,
      weekNew: weekNew,
      reviewTotal: reviewTotal,
      streakDays: streak,
      activeDays30: activeDays.length,
      topModules: WrongQuestionAnalytics.ranked(
        analytics.modules,
      ).take(5).toList(),
      weakTags: WrongQuestionAnalytics.ranked(
        analytics.weakPoints,
      ).take(8).toList(),
      errorTypes: WrongQuestionAnalytics.ranked(
        analytics.errors,
      ).take(5).toList(),
      weekly: weekly,
    );
  }
}

DateTime _dayOf(int millisecondsSinceEpoch) {
  final d = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
  return DateTime(d.year, d.month, d.day);
}

/// 画像里的一周（用于学习节奏柱状图）。
class PortraitWeek {
  const PortraitWeek({required this.start, required this.count});

  final DateTime start;
  final int count;

  String get label => '${start.month}/${start.day}';
}
