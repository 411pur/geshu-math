import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'student_insight_models.dart';

export 'student_insight_models.dart'; // 纯模型（可在 VM 单测）

/// 学习画像 Notifier：自动统计 + 每次讲解的具体错误点时间线（完整、可追溯）。
/// 注入 AI 时用 [StudentInsight.buildPromptInsight] 只取总结性内容。
class StudentInsightNotifier extends Notifier<StudentInsight> {
  static const _key = 'geshu_math_student_insight';
  static const _maxTrace = 200; // 时间线上限（防 localStorage 膨胀）

  @override
  StudentInsight build() {
    try {
      final raw = web.window.localStorage.getItem(_key);
      if (raw != null && raw.isNotEmpty) {
        return StudentInsight.fromJson(json.decode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return const StudentInsight();
  }

  void _persist(StudentInsight cur) {
    try {
      web.window.localStorage.setItem(_key, json.encode(cur.toJson()));
    } catch (_) {}
  }

  /// 从错题统计 JSON（StudentStatsBuilder 输出）更新画像，保留手填弱点与错误点时间线。
  void recordStats(String? statsJson) {
    int total = 0, week = 0, mastered = 0, unmastered = 0, reviews = 0;
    final modules = <String>[];
    final weaks = <String>[];
    if (statsJson != null && statsJson.isNotEmpty) {
      try {
        final j = json.decode(statsJson) as Map<String, dynamic>;
        total = (j['total_wrong_questions'] as num?)?.toInt() ?? 0;
        week = (j['week_new'] as num?)?.toInt() ?? 0;
        mastered = (j['mastered_rate'] as num?)?.toInt() ?? 0;
        unmastered = (j['unmastered_rate'] as num?)?.toInt() ?? 0;
        reviews = (j['total_reviews'] as num?)?.toInt() ?? 0;
        modules.addAll((j['top_modules'] as List?)?.map((e) => e.toString()) ?? const []);
        weaks.addAll((j['weak_tags'] as List?)?.map((e) => e.toString()) ?? const []);
      } catch (_) {}
    }
    final updated = StudentInsight(
      totalWrong: total,
      weekNew: week,
      masteredRate: mastered,
      unmasteredRate: unmastered,
      totalReviews: reviews,
      topModules: modules,
      weakTags: weaks,
      manualWeakPoints: state.manualWeakPoints,
      errorTrace: state.errorTrace,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    state = updated;
    _persist(updated);
  }

  /// 手动编辑薄弱点说明（供 AI 参考与用户自述）。
  void setManualWeakPoints(String text) {
    final updated = StudentInsight(
      totalWrong: state.totalWrong,
      weekNew: state.weekNew,
      masteredRate: state.masteredRate,
      unmasteredRate: state.unmasteredRate,
      totalReviews: state.totalReviews,
      topModules: state.topModules,
      weakTags: state.weakTags,
      manualWeakPoints: text.trim(),
      errorTrace: state.errorTrace,
      updatedAt: state.updatedAt,
    );
    state = updated;
    _persist(updated);
  }

  /// 记录一次讲解产生的「具体错误点」到时间线（完整、可追溯）。
  /// [source]：expert=专家版 / quick=快速版；讲解结果中的错因/考点/学生疑问全部入档。
  void recordSession({
    required String source,
    required String questionText,
    Map<String, dynamic>? explanation,
    Map<String, dynamic>? processedQuestion,
    List<String>? studentDoubts,
  }) {
    final entry = buildErrorTraceEntry(
      source: source,
      questionText: questionText,
      explanation: explanation,
      processedQuestion: processedQuestion,
      studentDoubts: studentDoubts,
    );
    // 只记录"有具体错误点"的条目（错因分析/考点/学生疑问至少一项）
    if (entry['fingerprint'] == '未分类' &&
        entry['key_point'].toString().isEmpty &&
        entry['doubt'].toString().isEmpty) {
      return;
    }
    final trace = [...state.errorTrace, entry];
    final trimmed = trace.length > _maxTrace ? trace.sublist(trace.length - _maxTrace) : trace;
    final updated = StudentInsight(
      totalWrong: state.totalWrong,
      weekNew: state.weekNew,
      masteredRate: state.masteredRate,
      unmasteredRate: state.unmasteredRate,
      totalReviews: state.totalReviews,
      topModules: state.topModules,
      weakTags: state.weakTags,
      manualWeakPoints: state.manualWeakPoints,
      errorTrace: trimmed,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    state = updated;
    _persist(updated);
  }
}

final studentInsightProvider =
    NotifierProvider<StudentInsightNotifier, StudentInsight>(
  StudentInsightNotifier.new,
);