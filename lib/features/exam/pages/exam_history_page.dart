import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../providers/exam_providers.dart';

class ExamHistoryPage extends ConsumerWidget {
  const ExamHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exams = ref.watch(examHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('考情历史')),
      body: exams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('读取考情失败：$error')),
        data: (items) => items.isEmpty
            ? const EmptyStateWidget(message: '暂无考试记录，请先完成一次考试分析')
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: items.length,
                itemBuilder: (_, i) =>
                    AppReveal(index: i, child: _card(context, items[i])),
              ),
      ),
    );
  }

  Widget _card(BuildContext context, dynamic exam) {
    final total = exam.totalScore as double? ?? 0;
    final score = exam.studentScore as double? ?? 0;
    final rate = total <= 0 ? 0.0 : score / total;
    final color = rate >= 0.8
        ? AppColors.accent
        : rate >= 0.6
        ? AppColors.warning
        : AppColors.error;
    final date = DateTime.fromMillisecondsSinceEpoch(exam.examDate as int);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            '${score.toInt()}',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ),
        title: Text(exam.examName as String),
        subtitle: Text(
          '${DateFormat('yyyy-MM-dd').format(date)} · ${score.toStringAsFixed(0)}/${total.toStringAsFixed(0)} 分',
        ),
        trailing: Text(
          '${(rate * 100).round()}%',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        onTap: () => context.go('/exam/detail/${exam.id}'),
      ),
    );
  }
}
