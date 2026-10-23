import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_provider.dart';
import '../../../core/network/sse_parser.dart';
import '../../knowledge/providers/knowledge_providers.dart';
import '../../wrong_question/providers/wrong_question_providers.dart';
import 'knowledge_label_mapper.dart';
import '../models/wrong_question_analytics.dart';

/// 一次报告生成的产出：正文 + AI 推荐优先练习的错题 id。
class ReportResult {
  final String content;
  final List<int> recommendedIds;
  const ReportResult(this.content, this.recommendedIds);
}

/// 学习报告生成器：拉取错题 → 拼数据（含 id 供 AI 引用）→ AI 流式生成
/// → 解析末尾「推荐练习」题目 id。报告页与登录补发共用。
class ReportGenerator {
  ReportGenerator._();

  /// 生成过去 [days] 天的学习报告。错题不足时返回空 content。
  static Future<ReportResult> generate(
    WidgetRef ref, {
    required int days,
  }) async {
    final source = ref.read(wrongQuestionDataSourceProvider);
    final all = source.getAllPaginated(limit: source.count());
    final analytics = WrongQuestionAnalytics(
      all,
      now: DateTime.now(),
      days: days,
    );
    final filtered = analytics.questions;
    if (filtered.isEmpty) return const ReportResult('', []);

    // 格式化为 JSON，附带知识图谱细化标签路径；每道题带上 id 供 AI 引用推荐
    final graphNodes = ref.read(knowledgeDataSourceProvider).getAll();
    final mapper = KnowledgeLabelMapper(graphNodes);

    final questions = filtered.map((w) {
      final paths = mapper.match(w);
      return {
        'id': w.id,
        'topic': w.topic ?? '',
        'subTopic': w.subTopic ?? '',
        'questionText': w.questionText,
        'createdAt': w.createdAt,
        'mastery': w.mastery,
        'reviewCount': w.reviewCount,
        'lastReviewedAt': w.lastReviewedAt,
        'difficultyLevel': w.difficultyLevel,
        'knowledge_paths': paths,
      };
    }).toList();

    final studentData = json.encode({
      'wrong_questions': questions,
      'statistics': {
        'total': analytics.total,
        'mastery_counts': analytics.mastery,
        'modules': analytics.modules,
        'error_types': analytics.errors,
        'pending_knowledge_points': analytics.weakPoints,
        'note': '掌握情况为当前手动标记；错题收录增多不代表成绩退步；未记录错因不能推断。',
      },
    });
    final client = ref.read(aiApiClientProvider);

    String full = '';
    await for (final event in client.sendReportMessage(
      studentDataJson: studentData,
      days: days,
      grade: '',
    )) {
      if (event is MessageChunk) {
        full += event.answer;
      } else if (event is StreamError) {
        throw Exception(event.message);
      } else if (event is MessageEnd) {
        full = event.fullAnswer;
      }
    }
    return ReportResult(full, extractRecommendedIds(full));
  }

  /// 从报告末尾解析「【推荐练习】题目ID：1、5、12」；未命中返回空。
  static List<int> extractRecommendedIds(String report) {
    if (report.isEmpty) return const [];
    final m = RegExp(
      r'【推荐练习】\s*题目ID\s*[:：]\s*([0-9、，,;；\s]+)',
    ).firstMatch(report);
    if (m == null) return const [];
    return RegExp(r'\d+')
        .allMatches(m.group(1)!)
        .map((x) => int.tryParse(x.group(0) ?? '') ?? 0)
        .where((id) => id > 0)
        .toList();
  }
}
