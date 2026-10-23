import 'dart:convert';
import 'package:web/web.dart' as web;

import 'report_schedule_model.dart';

export 'report_schedule_model.dart';

/// 学习报告定时持久化服务：
/// localStorage 存储定时设置、上次发送时间、最近一次报告内容、推荐练习题目 id；
/// 判定逻辑（到点/补发）见 [ReportScheduleLogic]。
class ReportScheduleService {
  ReportScheduleService._();

  static const scheduleKey = 'geshu_math_report_schedule';
  static const lastSentKey = 'geshu_math_report_last_sent';
  static const contentKey = 'geshu_math_report_content';
  static const recommendedKey = 'geshu_math_report_rec_ids';
  static const metadataKey = 'geshu_math_report_metadata';

  // ── 持久化 ────────────────────────────────────────────

  static ReportSchedule loadSchedule() {
    try {
      final raw = web.window.localStorage.getItem(scheduleKey);
      if (raw != null && raw.isNotEmpty) {
        return ReportSchedule.fromJson(
          json.decode(raw) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return const ReportSchedule();
  }

  static void saveSchedule(ReportSchedule s) {
    try {
      web.window.localStorage.setItem(scheduleKey, json.encode(s.toJson()));
    } catch (_) {}
  }

  static DateTime? loadLastSent() {
    try {
      final raw = web.window.localStorage.getItem(lastSentKey);
      if (raw != null && raw.isNotEmpty) return DateTime.parse(raw);
    } catch (_) {}
    return null;
  }

  /// 记录已发送（供定时触发/登录补发共用）。
  static void markSent([DateTime? t]) {
    try {
      final ts = (t ?? DateTime.now()).toIso8601String();
      web.window.localStorage.setItem(lastSentKey, ts);
    } catch (_) {}
  }

  static String? loadReportContent() {
    try {
      final raw = web.window.localStorage.getItem(contentKey);
      return (raw != null && raw.isNotEmpty) ? raw : null;
    } catch (_) {}
    return null;
  }

  static void saveReportContent(String content, {int days = 7}) {
    try {
      web.window.localStorage.setItem(contentKey, content);
      web.window.localStorage.setItem(
        metadataKey,
        json.encode({
          'days': days,
          'generatedAt': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  static Map<String, dynamic> _metadata() {
    try {
      return json.decode(web.window.localStorage.getItem(metadataKey) ?? '{}')
          as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static int? loadReportDays() {
    final value = _metadata()['days'];
    return value is num && value > 0 ? value.toInt() : null;
  }

  static DateTime? loadReportTime() =>
      DateTime.tryParse(_metadata()['generatedAt']?.toString() ?? '');

  static List<int> loadRecommendedIds() {
    try {
      final raw = web.window.localStorage.getItem(recommendedKey);
      if (raw != null && raw.isNotEmpty) {
        final list = json.decode(raw) as List;
        return list
            .map((e) => (e as num).toInt())
            .where((id) => id > 0)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  static void saveRecommendedIds(List<int> ids) {
    try {
      web.window.localStorage.setItem(recommendedKey, json.encode(ids));
    } catch (_) {}
  }

  // ── 便捷包装（注入上次发送时间）───────────────────────

  static bool isDueNow(ReportSchedule s, DateTime now) =>
      ReportScheduleLogic.isDueNow(s, now, loadLastSent());

  static bool shouldTriggerMissed(ReportSchedule s, DateTime now) =>
      ReportScheduleLogic.shouldTriggerMissed(s, now, loadLastSent());
}
