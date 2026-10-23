import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geshu_math/domain/entities/wrong_question_entity.dart';
import 'package:geshu_math/features/report/models/portrait_summary.dart';

WrongQuestion _q({
  required int id,
  required String topic,
  required String subTopic,
  required int mastery,
  required DateTime created,
  String? errorType,
  List<String> tags = const [],
  int reviewCount = 0,
}) {
  return WrongQuestion(
    id: id,
    topic: topic,
    subTopic: subTopic,
    questionText: '第 $id 题',
    createdAt: created.millisecondsSinceEpoch,
    mastery: mastery,
    reviewCount: reviewCount,
    tagsJson: jsonEncode(tags),
    guidanceResultJson: errorType == null
        ? null
        : jsonEncode({
            'guidance_result': {'error_type': errorType},
          }),
  );
}

void main() {
  final now = DateTime(2026, 10, 23, 15, 30);

  test('空错题本：没有数据、周柱全为 0', () {
    final s = PortraitSummary.from(const [], now: now);
    expect(s.hasData, isFalse);
    expect(s.total, 0);
    expect(s.headline, '还没有错题记录');
    expect(s.weekly, hasLength(8));
    expect(s.weekly.every((w) => w.count == 0), isTrue);
  });

  test('掌握度、模块、薄弱点与错因按错题本聚合', () {
    final s = PortraitSummary.from([
      _q(
        id: 1,
        topic: '函数',
        subTopic: '二次函数最值',
        mastery: 2,
        created: now,
        errorType: '概念混淆',
        tags: ['二次函数'],
        reviewCount: 3,
      ),
      _q(
        id: 2,
        topic: '函数',
        subTopic: '二次函数最值',
        mastery: 0,
        created: now,
        errorType: '计算失误',
        tags: ['二次函数'],
        reviewCount: 1,
      ),
      _q(
        id: 3,
        topic: '平面几何',
        subTopic: '相似三角形',
        mastery: 1,
        created: now,
        tags: ['辅助线'],
      ),
    ], now: now);

    expect(s.total, 3);
    expect(s.pending, 2);
    expect(s.masteredPercent, 33);
    expect(s.reviewTotal, 4);
    expect(s.topModules.first.key, '函数');
    expect(s.topModules.first.value, 2);
    // 已掌握题的标签不计入薄弱点
    expect(s.weakTags.map((e) => e.key), containsAll(['二次函数', '辅助线']));
    expect(s.weakTags.first.value, 1);
    expect(
      s.errorTypes.map((e) => e.key),
      containsAll(['概念混淆', '计算失误', '未记录']),
    );
  });

  test('本周新增、连续天数与近 8 周分布按日历日计算', () {
    final s = PortraitSummary.from([
      _q(id: 1, topic: '函数', subTopic: 'A', mastery: 0, created: now),
      _q(
        id: 2,
        topic: '函数',
        subTopic: 'A',
        mastery: 0,
        created: now.subtract(const Duration(days: 1)),
      ),
      _q(
        id: 3,
        topic: '函数',
        subTopic: 'A',
        mastery: 0,
        created: now.subtract(const Duration(days: 2)),
      ),
      _q(
        id: 4,
        topic: '函数',
        subTopic: 'A',
        mastery: 0,
        created: now.subtract(const Duration(days: 40)),
      ),
    ], now: now);

    expect(s.weekNew, 3);
    expect(s.streakDays, 3);
    expect(s.activeDays30, 3);
    expect(s.weekly, hasLength(8));
    expect(s.weekly.last.count, 1, reason: '最后一桶是今天');
    expect(s.weekly.fold<int>(0, (a, w) => a + w.count), 4);
    expect(s.weekly.first.start.isBefore(s.weekly.last.start), isTrue);
  });

  test('今天还没记录时，连续天数从昨天起算', () {
    final s = PortraitSummary.from([
      _q(
        id: 1,
        topic: '函数',
        subTopic: 'A',
        mastery: 0,
        created: now.subtract(const Duration(days: 1)),
      ),
      _q(
        id: 2,
        topic: '函数',
        subTopic: 'A',
        mastery: 0,
        created: now.subtract(const Duration(days: 2)),
      ),
    ], now: now);

    expect(s.streakDays, 2);
    expect(s.weekNew, 2);
  });

  test('未来日期的记录不计入本周与连续天数', () {
    final s = PortraitSummary.from([
      _q(
        id: 1,
        topic: '函数',
        subTopic: 'A',
        mastery: 0,
        created: now.add(const Duration(days: 3)),
      ),
    ], now: now);

    expect(s.total, 1, reason: '全量统计仍包含该记录');
    expect(s.weekNew, 0);
    expect(s.streakDays, 0);
    expect(s.weekly.fold<int>(0, (a, w) => a + w.count), 0);
  });
}
