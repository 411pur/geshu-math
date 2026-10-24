import '../../../domain/entities/wrong_question_entity.dart';
import 'wrong_question_analytics.dart';

enum PracticeOutcome {
  independent('独立完成'),
  prompted('需要提示'),
  retry('仍不会');

  const PracticeOutcome(this.label);
  final String label;
}

/// Self-reported evidence, deliberately separate from mastery and AI diagnoses.
class PracticeRecord {
  const PracticeRecord({
    required this.id,
    required this.questionId,
    required this.at,
    required this.outcome,
    required this.viewedExplanation,
  });
  final String id;
  final int questionId, at;
  final PracticeOutcome outcome;
  final bool viewedExplanation;

  Map<String, dynamic> toJson() => {
    'id': id,
    'questionId': questionId,
    'at': at,
    'outcome': outcome.name,
    'viewedExplanation': viewedExplanation,
  };

  static PracticeRecord? parse(dynamic value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['questionId'] is! int ||
        value['at'] is! int ||
        value['at'] <= 0) {
      return null;
    }
    final matches = PracticeOutcome.values.where(
      (o) => o.name == value['outcome'],
    );
    if (matches.isEmpty) return null;
    final viewed = value['viewedExplanation'] == true;
    return PracticeRecord(
      id: value['id'],
      questionId: value['questionId'],
      at: value['at'],
      outcome: viewed && matches.first == PracticeOutcome.independent
          ? PracticeOutcome.prompted
          : matches.first,
      viewedExplanation: viewed,
    );
  }
}

class LearningMemory {
  const LearningMemory({this.records = const [], this.preference = '逐步推导'});
  static const preferences = ['逐步推导', '先看图示', '先给提示'];
  final List<PracticeRecord> records;
  final String preference;

  factory LearningMemory.fromJson(dynamic value) {
    if (value is! Map) return const LearningMemory();
    final raw = value['records'];
    final parsed = raw is List
        ? raw.map(PracticeRecord.parse).whereType<PracticeRecord>().toList()
        : <PracticeRecord>[];
    // Latest entries win on duplicate ids; keep storage bounded.
    final unique = {
      for (final record in parsed) record.id: record,
    }.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    return LearningMemory(
      records: unique.length > 500
          ? unique.sublist(unique.length - 500)
          : unique,
      preference: preferences.contains(value['preference'])
          ? value['preference']
          : preferences.first,
    );
  }
  Map<String, dynamic> toJson() => {
    'version': 1,
    'preference': preference,
    'records': records.map((r) => r.toJson()).toList(),
  };

  List<PracticeRecord> validRecords(
    List<WrongQuestion> questions,
    DateTime now,
  ) {
    final ids = questions.map((q) => q.id).toSet();
    return records
        .where(
          (r) =>
              ids.contains(r.questionId) && r.at <= now.millisecondsSinceEpoch,
        )
        .toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  String prompt(List<WrongQuestion> questions, DateTime now) {
    final byId = {for (final q in questions) q.id: q};
    final recent = validRecords(questions, now).take(8);
    return '【学生自选讲解方式】$preference\n'
        '【练习反馈：学生自评，不是考试成绩；只用于相关知识点的建议，不据此断言能力】\n'
        '${recent.map((r) => '- ${byId[r.questionId]?.subTopic ?? byId[r.questionId]?.topic ?? "未分类"}：${r.outcome.label}（${DateTime.fromMillisecondsSinceEpoch(r.at).toIso8601String().substring(0, 10)}，${r.viewedExplanation ? "已查看讲解" : "未在本次练习查看讲解"}）').join('\n')}';
  }
}

class LearningSuggestion {
  const LearningSuggestion(this.question, this.reason, this.priority);
  final WrongQuestion question;
  final String reason;
  final int priority;
}

List<LearningSuggestion> suggestPractice(
  List<WrongQuestion> questions,
  LearningMemory memory,
  DateTime now,
) {
  final latest = <int, PracticeRecord>{};
  for (final record in memory.validRecords(questions, now)) {
    latest.putIfAbsent(record.questionId, () => record);
  }
  final suggestions = <LearningSuggestion>[];
  for (final q in questions) {
    if (q.id == null) continue;
    final record = latest[q.id];
    if (record != null) {
      final age = now.difference(
        DateTime.fromMillisecondsSinceEpoch(record.at),
      );
      if (record.outcome == PracticeOutcome.independent) {
        if (age < const Duration(days: 7)) continue;
        suggestions.add(LearningSuggestion(q, '上次自评独立完成已过 7 天，换个时间再试一次。', 1));
      } else {
        suggestions.add(
          LearningSuggestion(
            q,
            record.outcome == PracticeOutcome.retry
                ? '上次反馈仍不会，建议先回顾概念，再尝试解题。'
                : '上次需要提示，这次先尝试独立完成关键步骤。',
            record.outcome == PracticeOutcome.retry ? 5 : 4,
          ),
        );
      }
    } else if (WrongQuestionAnalytics.masteryOf(q) != 2) {
      suggestions.add(
        LearningSuggestion(q, '这道题标记为待巩固，还没有练习反馈；先试一次，了解当前情况。', 3),
      );
    }
  }
  suggestions.sort((a, b) {
    final priority = b.priority.compareTo(a.priority);
    return priority != 0 ? priority : a.question.id!.compareTo(b.question.id!);
  });
  return suggestions;
}
