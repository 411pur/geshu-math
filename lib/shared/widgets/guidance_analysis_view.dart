import 'package:flutter/material.dart';

import '../../data/datasources/remote/dify_response_models.dart';

/// 题目解析模型（Dify 错因诊断工作流）产出的「分析过程」展示组件。
///
/// 把 [GuidanceResult] 的 7 段模板（正确答案 / 标准分步解析 / 错因分析 /
/// 知识点回顾 / 易错警示 / 变式训练 / 错题档案）渲染成可读卡片。
/// 扫描识题页与错题指导页共用同一套视觉，避免两套重复实现。
class GuidanceAnalysisView extends StatelessWidget {
  final GuidanceResult guidance;
  const GuidanceAnalysisView({super.key, required this.guidance});

  @override
  Widget build(BuildContext context) {
    final r = guidance;
    final hasTemplate =
        r.title.isNotEmpty || r.stepAnalysis.isNotEmpty || r.correctAnswer.isNotEmpty;
    final theme = Theme.of(context);
    final children = <Widget>[];

    if (hasTemplate) {
      if (r.title.isNotEmpty) {
        children.add(Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(r.title, style: theme.textTheme.titleSmall),
          ),
        ));
        children.add(const SizedBox(height: 8));
      }
      children.add(_section(context, '1. 本题正确答案', r.correctAnswer));
      children.add(_section(
        context,
        '2. 标准分步解析（分析过程）',
        r.stepAnalysis,
        highlight: true,
      ));
      children.add(_section(context, '3. 精准错因分析', r.errorAnalysis));
      children.add(_section(context, '4. 核心知识点回顾', r.knowledgeReview));
      children.add(_section(context, '5. 本题易错警示', r.warning));
      children.add(_section(context, '6. 举一反三·变式训练', r.variation));
      children.add(_section(context, '7. 错题档案信息', r.archive, muted: true));
    } else {
      children.add(_section(context, '题目分析', r.analysis));
      children.add(_section(context, '正确解法', r.correctSolution));
    }

    if (r.knowledgePoints.isNotEmpty) {
      children.add(const SizedBox(height: 12));
      children.add(Text('关联知识点', style: theme.textTheme.titleSmall));
      children.add(const SizedBox(height: 8));
      children.add(Wrap(
        spacing: 6,
        children: r.knowledgePoints.map((kp) => Chip(label: Text(kp))).toList(),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _section(BuildContext context, String label, String content,
      {bool highlight = false, bool muted = false}) {
    if (content.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: highlight ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: muted ? theme.colorScheme.onSurfaceVariant : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
