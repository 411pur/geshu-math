import 'dart:convert';

import '../../../domain/entities/wrong_question_entity.dart';

/// Pure, deterministic statistics. A period includes today and the preceding
/// calendar days; future and unknown dates never become trend observations.
class WrongQuestionAnalytics {
  WrongQuestionAnalytics(
    List<WrongQuestion> source, {
    required this.now,
    this.days,
  }) {
    if (days != null && (days! < 1 || days! > 366)) {
      throw ArgumentError.value(days, 'days', 'must be between 1 and 366');
    }
    final start = days == null
        ? null
        : DateTime(now.year, now.month, now.day - days! + 1);
    questions = source
        .where(
          (q) =>
              start == null ||
              (q.createdAt >= start.millisecondsSinceEpoch &&
                  q.createdAt <= now.millisecondsSinceEpoch),
        )
        .toList();
    mastery = List.filled(3, 0);
    for (final q in questions) {
      mastery[masteryOf(q)]++;
      _increment(modules, _label(q.topic, '未分类'));
      final error = errorType(q);
      _increment(errors, error);
      if (error != '未记录') classifiedErrors++;
      if (masteryOf(q) != 2) {
        for (final tag in knowledgeLabels(q)) {
          _increment(weakPoints, tag);
        }
      }
    }
    daily = days == null
        ? []
        : List.generate(days!, (i) {
            final date = DateTime(now.year, now.month, now.day - days! + 1 + i);
            final end = DateTime(date.year, date.month, date.day + 1);
            return DailyWrongCount(
              date,
              questions
                  .where(
                    (q) =>
                        q.createdAt >= date.millisecondsSinceEpoch &&
                        q.createdAt < end.millisecondsSinceEpoch,
                  )
                  .length,
            );
          });
  }

  final DateTime now;
  final int? days;
  late final List<WrongQuestion> questions;
  late final List<int> mastery;
  late final List<DailyWrongCount> daily;
  final modules = <String, int>{};
  final errors = <String, int>{};
  final weakPoints = <String, int>{};
  int classifiedErrors = 0;
  int get total => questions.length;
  int get pending => mastery[0] + mastery[1];
  int get masteredPercent =>
      total == 0 ? 0 : (mastery[2] * 100 / total).round();

  static int masteryOf(WrongQuestion q) =>
      q.mastery >= 0 && q.mastery <= 2 ? q.mastery : 0;

  static List<MapEntry<String, int>> ranked(Map<String, int> counts) =>
      counts.entries.toList()..sort((a, b) {
        final comparison = b.value.compareTo(a.value);
        return comparison == 0 ? a.key.compareTo(b.key) : comparison;
      });

  static Set<String> knowledgeLabels(WrongQuestion q) {
    final labels = <String>{};
    try {
      final decoded = jsonDecode(q.tagsJson ?? '[]');
      if (decoded is List) {
        labels.addAll(
          decoded
              .whereType<String>()
              .map((e) => e.trim())
              .where(
                (e) =>
                    e.isNotEmpty &&
                    !{
                      '概念混淆',
                      '计算失误',
                      '审题偏差',
                      '模型误用',
                      '公式错误',
                      '单位错误',
                      '粗心',
                      '其他',
                    }.contains(e),
              ),
        );
      }
    } catch (_) {
      /* Legacy malformed tags fall back to the stored topic. */
    }
    if (labels.isEmpty) labels.add(_label(q.subTopic, _label(q.topic, '未分类')));
    return labels;
  }

  static String errorType(WrongQuestion q) {
    try {
      final decoded = jsonDecode(q.guidanceResultJson ?? '{}');
      if (decoded is Map) {
        final guidance = decoded['guidance_result'] is Map
            ? decoded['guidance_result'] as Map
            : decoded;
        final value = guidance['error_type'];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    } catch (_) {
      /* Missing structured diagnosis is not inferred from prose. */
    }
    return '未记录';
  }

  static String _label(String? label, String fallback) =>
      label == null || label.trim().isEmpty ? fallback : label.trim();
  static void _increment(Map<String, int> counts, String label) =>
      counts[label] = (counts[label] ?? 0) + 1;
}

class DailyWrongCount {
  const DailyWrongCount(this.date, this.count);
  final DateTime date;
  final int count;
}

/// A diagnosis session is an observation, not necessarily a distinct question.
class RecurringError {
  RecurringError(this.label, this.records);
  final String label;
  final List<Map<String, dynamic>> records;

  static List<RecurringError> fromTrace(List<Map<String, dynamic>> trace) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final entry in trace) {
      final fingerprint = entry['fingerprint'];
      if (fingerprint is! String ||
          fingerprint.trim().isEmpty ||
          fingerprint == '未分类') {
        continue;
      }
      groups.putIfAbsent(fingerprint, () => []).add(entry);
    }
    return groups.entries.map((entry) {
      final records = entry.value.toList()
        ..sort(
          (a, b) => (b['ts'] is num ? b['ts'] as num : 0).compareTo(
            a['ts'] is num ? a['ts'] as num : 0,
          ),
        );
      final latest = records.first;
      final label =
          [latest['sub_topic'], latest['error_type'], latest['key_concept']]
              .whereType<String>()
              .where((e) => e.trim().isNotEmpty)
              .toSet()
              .join(' · ');
      return RecurringError(label.isEmpty ? entry.key : label, records);
    }).toList()..sort((a, b) {
      final order = b.records.length.compareTo(a.records.length);
      return order == 0 ? a.label.compareTo(b.label) : order;
    });
  }
}
