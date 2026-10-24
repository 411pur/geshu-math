import 'package:flutter_test/flutter_test.dart';
import 'package:geshu_math/domain/entities/wrong_question_entity.dart';
import 'package:geshu_math/features/report/models/learning_memory.dart';

void main() {
  final now = DateTime(2026, 10, 19, 12);
  final questions = [
    for (var i = 1; i <= 3; i++)
      WrongQuestion(
        id: i,
        topic: '力学',
        subTopic: '受力分析',
        questionText: '题 $i',
        createdAt: 1,
        mastery: i == 3 ? 2 : 0,
      ),
  ];
  PracticeRecord record(
    int id,
    PracticeOutcome outcome, {
    int days = 0,
    bool viewed = false,
  }) => PracticeRecord(
    id: '$id-$days',
    questionId: id,
    at: now.subtract(Duration(days: days)).millisecondsSinceEpoch,
    outcome: outcome,
    viewedExplanation: viewed,
  );

  test('old storage and malformed records load safely', () {
    expect(LearningMemory.fromJson({}).records, isEmpty);
    final memory = LearningMemory.fromJson({
      'preference': 'bad',
      'records': [
        null,
        {},
        {'at': 'bad'},
        record(1, PracticeOutcome.retry).toJson(),
      ],
    });
    expect(memory.preference, '逐步推导');
    expect(memory.records.length, 1);
    expect(
      LearningMemory.fromJson(memory.toJson()).records.single.outcome,
      PracticeOutcome.retry,
    );
  });
  test('viewed explanation cannot be imported as independent completion', () {
    final memory = LearningMemory.fromJson({
      'records': [
        record(1, PracticeOutcome.independent, viewed: true).toJson(),
      ],
    });
    expect(memory.records.single.outcome, PracticeOutcome.prompted);
  });
  test('feedback changes priority without mutating mastery', () {
    expect(
      suggestPractice(questions, const LearningMemory(), now).first.question.id,
      1,
    );
    final memory = LearningMemory(records: [record(2, PracticeOutcome.retry)]);
    expect(suggestPractice(questions, memory, now).first.question.id, 2);
    expect(questions[1].mastery, 0);
  });
  test(
    'latest feedback wins and independent completion has seven day cooldown',
    () {
      final memory = LearningMemory(
        records: [
          record(1, PracticeOutcome.retry, days: 1),
          record(1, PracticeOutcome.independent),
        ],
      );
      expect(
        suggestPractice(questions, memory, now).map((s) => s.question.id),
        [2],
      );
      final later = suggestPractice(
        questions,
        memory,
        now.add(const Duration(days: 7)),
      );
      expect(later.map((s) => s.question.id), [2, 1]);
      expect(later.last.reason, contains('7 天'));
    },
  );
  test(
    'deleted and future evidence cannot enter prompts or recommendations',
    () {
      final memory = LearningMemory(
        records: [
          record(99, PracticeOutcome.retry),
          record(1, PracticeOutcome.retry, days: -1),
        ],
      );
      expect(memory.validRecords(questions, now), isEmpty);
      expect(memory.prompt(questions, now), isNot(contains('仍不会')));
    },
  );
  test(
    'new struggle supersedes old manual mastered state, with visible reason',
    () {
      final memory = LearningMemory(
        records: [record(3, PracticeOutcome.prompted)],
      );
      final suggestion = suggestPractice(questions, memory, now).first;
      expect(suggestion.question.id, 3);
      expect(suggestion.reason, contains('需要提示'));
      expect(questions.last.mastery, 2);
    },
  );
  test('storage bounds records and deduplicates ids', () {
    final raw = [
      for (var i = 1; i <= 520; i++) record(i, PracticeOutcome.retry).toJson(),
    ];
    final memory = LearningMemory.fromJson({
      'records': [...raw, raw.last],
    });
    expect(memory.records.length, 500);
    expect(memory.records.map((r) => r.id).toSet().length, 500);
  });
}
