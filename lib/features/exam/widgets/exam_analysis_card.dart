import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/dify_response_models.dart';

class ExamAnalysisCard extends StatelessWidget {
  final AnalysisResult analysis;
  const ExamAnalysisCard({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('AI分析报告', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              analysis.overallAssessment,
              style: const TextStyle(height: 1.55),
            ),
            if (analysis.strengthAreas.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                '优势',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 6),
              ...analysis.strengthAreas.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${item.topic}（${(item.scoreRate * 100).round()}%）：${item.comment}',
                  ),
                ),
              ),
            ],
            if (analysis.weaknessAreas.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                '薄弱点',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 6),
              ...analysis.weaknessAreas.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${item.topic}（${(item.scoreRate * 100).round()}%）：${item.comment}',
                  ),
                ),
              ),
            ],
            if (analysis.improvementSuggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                '下一步建议',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...analysis.improvementSuggestions.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $item'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('下次考试目标：${analysis.nextExamPrediction}'),
            ),
          ],
        ),
      ),
    );
  }
}
