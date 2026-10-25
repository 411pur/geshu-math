import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/dify_response_models.dart';
import '../../../domain/entities/exam_entity.dart';
import '../providers/exam_providers.dart';
import '../widgets/exam_analysis_card.dart';

class ExamDetailPage extends ConsumerWidget {
  final int id;
  const ExamDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(examDetailProvider(id));
    final details = ref.watch(examQuestionDetailsProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('考试详情')),
      body: record.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('读取考试失败：$error')),
        data: (exam) => exam == null
            ? const Center(child: Text('考试记录不存在'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summary(context, exam),
                  if (exam.analysisResultJson?.isNotEmpty == true)
                    _analysis(exam.analysisResultJson!),
                  const SizedBox(height: 16),
                  const Text(
                    '逐题分析',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  details.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (error, _) => Text('读取逐题分析失败：$error'),
                    data: (items) => items.isEmpty
                        ? const Text('没有逐题数据')
                        : Column(children: items.map(_questionCard).toList()),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _summary(BuildContext context, ExamRecord exam) {
    final total = exam.totalScore ?? 0;
    final score = exam.studentScore ?? 0;
    final rate = total <= 0 ? 0.0 : score / total;
    final date = DateTime.fromMillisecondsSinceEpoch(exam.examDate);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              exam.examName,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('yyyy-MM-dd').format(date),
              style: const TextStyle(color: AppColors.mutedForeground),
            ),
            const SizedBox(height: 10),
            Text(
              '得分: ${score.toStringAsFixed(0)} / ${total.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '得分率: ${(rate * 100).round()}%',
              style: TextStyle(
                color: rate >= 0.8
                    ? AppColors.accent
                    : rate >= 0.6
                    ? AppColors.warning
                    : AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _analysis(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ExamAnalysisCard(
          analysis: AnalysisResult.fromJson(Map<String, dynamic>.from(parsed)),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _questionCard(ExamQuestionDetail item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (item.isWrong ? AppColors.error : AppColors.accent)
              .withValues(alpha: 0.12),
          child: Icon(
            item.isWrong ? Icons.close : Icons.check,
            color: item.isWrong ? AppColors.error : AppColors.accent,
          ),
        ),
        title: Text('第 ${item.questionNumber} 题 · ${item.topic ?? '未分类'}'),
        subtitle: Text(
          '得分 ${item.studentScore?.toStringAsFixed(0) ?? '?'}/${item.maxScore?.toStringAsFixed(0) ?? '?'}${item.errorType?.isNotEmpty == true ? ' · ${item.errorType}' : ''}',
        ),
        trailing: Chip(
          label: Text(item.isWrong ? '错误' : '正确'),
          backgroundColor: (item.isWrong ? AppColors.error : AppColors.accent)
              .withValues(alpha: 0.06),
        ),
      ),
    );
  }
}
