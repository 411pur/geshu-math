import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';

class ExamDetailPage extends ConsumerWidget {
  final int id;
  const ExamDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('考试详情')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('考试 #$id', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text('得分: 72 / 100', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('得分率: 72%', style: TextStyle(color: AppColors.warning)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('逐题分析', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ...List.generate(5, (i) => _questionCard(i + 1, i != 2)),
          ],
        ),
      ),
    );
  }

  Widget _questionCard(int num, bool correct) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: correct
              ? AppColors.accent.withValues(alpha: 0.12)
              : AppColors.error.withValues(alpha: 0.12),
          child: Icon(
            correct ? Icons.check : Icons.close,
            color: correct ? AppColors.accent : AppColors.error,
          ),
        ),
        title: Text('第 $num 题'),
        subtitle: Text(correct ? '得分 5/5' : '得分 3/5 · 错误类型: 公式应用'),
        trailing: Chip(
          label: Text(correct ? '正确' : '错误'),
          backgroundColor: correct
              ? AppColors.accent.withValues(alpha: 0.06)
              : AppColors.error.withValues(alpha: 0.06),
        ),
      ),
    );
  }
}