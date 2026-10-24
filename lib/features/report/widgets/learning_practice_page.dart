import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/styled_markdown.dart';
import '../providers/analytics_provider.dart';
import '../providers/learning_memory_provider.dart';
import 'analytics_question_sheet.dart';

void openLearningPractice(BuildContext context, LearningSuggestion suggestion) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _PracticePage(suggestion: suggestion),
    ),
  );
}

class _PracticePage extends ConsumerStatefulWidget {
  const _PracticePage({required this.suggestion});
  final LearningSuggestion suggestion;
  @override
  ConsumerState<_PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends ConsumerState<_PracticePage> {
  bool _viewed = false;
  bool _saved = false;
  @override
  Widget build(BuildContext context) {
    final q = widget.suggestion.question;
    final exists = ref
        .watch(analyticsQuestionsProvider)
        .any((item) => item.id == q.id);
    return Scaffold(
      appBar: AppBar(title: const Text('一次有针对性的练习')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                q.subTopic ?? q.topic ?? '数学练习',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.suggestion.reason,
                style: const TextStyle(
                  color: AppColors.mutedForeground,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '先自己试一试',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              StyledMarkdown(
                data: q.questionText.isEmpty ? '请根据下方题图作答。' : q.questionText,
              ),
              if (q.questionImagePath?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _questionImage(q.questionImagePath!),
                ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _viewed = true);
                    openAnalyticsQuestion(context, ref, q);
                  },
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('查看原有讲解'),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                '这次完成得怎么样？',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _viewed ? '本次已打开讲解，请记录借助讲解后的情况。' : '按实际情况记录；这会帮助调整下一次练习建议。',
                style: const TextStyle(
                  color: AppColors.mutedForeground,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              if (!exists) const Text('这道题已从错题本移除，无法保存练习反馈。'),
              if (_saved) ...[
                const Text('已记录。回到档案查看更新后的建议，也可以撤销误记。'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('回到学习档案'),
                ),
              ] else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: PracticeOutcome.values
                      .map(
                        (outcome) => OutlinedButton(
                          onPressed:
                              !exists ||
                                  (_viewed &&
                                      outcome == PracticeOutcome.independent)
                              ? null
                              : () {
                                  try {
                                    ref
                                        .read(learningMemoryProvider.notifier)
                                        .record(
                                          q.id!,
                                          outcome,
                                          viewedExplanation: _viewed,
                                        );
                                    setState(() => _saved = true);
                                  } catch (_) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('反馈未保存，请检查存储空间后重试。'),
                                      ),
                                    );
                                  }
                                },
                          child: Text(outcome.label),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionImage(String path) {
    try {
      return Image.memory(
        base64Decode(path.split(',').last),
        errorBuilder: (_, _, _) => const Text('题图加载失败，请返回错题本检查原图。'),
      );
    } catch (_) {
      return const Text('题图加载失败，请返回错题本检查原图。');
    }
  }
}
