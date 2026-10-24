import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/learning_memory.dart';
import '../models/wrong_question_analytics.dart';

/// Compact, practical overview used at the top of the learning report.
class LearningReportSummaryCard extends StatelessWidget {
  const LearningReportSummaryCard({
    super.key,
    required this.data,
    required this.days,
    required this.nextSuggestion,
    required this.onPractice,
    required this.onAddQuestion,
  });

  final WrongQuestionAnalytics data;
  final int days;
  final LearningSuggestion? nextSuggestion;
  final VoidCallback? onPractice;
  final VoidCallback onAddQuestion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    '近 $days 天学习概览',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '数据来源：当前错题本',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _metrics(),
              const SizedBox(height: 16),
              _trend(context),
            ],
          );
          final action = _nextAction(context);
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summary, const SizedBox(height: 18), action],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 7, child: summary),
                const SizedBox(width: 24),
                Container(width: 1, color: AppColors.border),
                const SizedBox(width: 24),
                Expanded(flex: 4, child: action),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _metrics() {
    return Row(
      children: [
        Expanded(child: _metric('本期收录', '${data.total}', '道错题')),
        _metricDivider(),
        Expanded(child: _metric('待巩固', '${data.pending}', '未掌握 + 复习中')),
        _metricDivider(),
        Expanded(
          child: _metric(
            '已掌握',
            data.total == 0 ? '—' : '${data.masteredPercent}%',
            '按当前标记',
          ),
        ),
      ],
    );
  }

  Widget _metric(String label, String value, String note) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.foreground,
            fontSize: 30,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.foreground,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          note,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.mutedForeground,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _metricDivider() => Container(
    width: 1,
    height: 54,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: AppColors.border,
  );

  Widget _trend(BuildContext context) {
    final source = data.daily.length > 14
        ? data.daily.sublist(data.daily.length - 14)
        : data.daily;
    final maximum = source.fold<int>(1, (max, item) {
      return item.count > max ? item.count : max;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '错题收录趋势',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
            const Spacer(),
            Text(
              source.isEmpty
                  ? '—'
                  : '${source.first.date.month}/${source.first.date.day} — '
                        '${source.last.date.month}/${source.last.date.day}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 58,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gap = source.length > 20 ? 2.0 : 4.0;
              final width = source.isEmpty
                  ? 0.0
                  : math.max(
                      2.0,
                      (constraints.maxWidth - gap * (source.length - 1)) /
                          source.length,
                    );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < source.length; index++) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      width: width,
                      height: 8 + 50 * (source[index].count / maximum),
                      decoration: BoxDecoration(
                        color: source[index].count == 0
                            ? AppColors.border
                            : AppColors.primary.withValues(alpha: .82),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    if (index != source.length - 1) SizedBox(width: gap),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _nextAction(BuildContext context) {
    final suggestion = nextSuggestion;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '下一步练习',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (suggestion == null) ...[
            Text('暂无优先练习', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '近期自评独立完成的题目会暂缓推荐。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAddQuestion,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('去添加错题'),
            ),
          ] else ...[
            Text(
              suggestion.question.subTopic ??
                  suggestion.question.topic ??
                  '回顾这道错题',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              suggestion.reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onPractice,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('开始练习'),
            ),
          ],
        ],
      ),
    );
  }
}
