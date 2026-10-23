import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/motion/app_motion.dart';
import '../../../domain/entities/wrong_question_entity.dart';
import '../../home/widgets/donut_chart.dart';
import '../models/wrong_question_analytics.dart';

typedef ShowAnalyticsQuestions =
    void Function(String title, List<WrongQuestion> questions);

class AnalyticsDashboard extends StatelessWidget {
  const AnalyticsDashboard({
    super.key,
    required this.data,
    required this.onShowQuestions,
    this.profile = false,
    this.trace = const [],
  });
  final WrongQuestionAnalytics data;
  final ShowAnalyticsQuestions onShowQuestions;
  final bool profile;
  final List<Map<String, dynamic>> trace;

  static const colors = [AppColors.error, AppColors.warning, AppColors.accent];
  static const labels = ['未掌握', '复习中', '已掌握'];

  @override
  Widget build(BuildContext context) {
    final recurring = RecurringError.fromTrace(
      trace,
    ).where((e) => e.records.length > 1).take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = ((constraints.maxWidth - 24) / 3).clamp(0.0, 180.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metric(
                  profile ? '错题本总量' : '本期收录',
                  '${data.total}',
                  '道错题',
                  width,
                ),
                const SizedBox(width: 12),
                _metric('待巩固', '${data.pending}', '未掌握 + 复习中', width),
                const SizedBox(width: 12),
                _metric(
                  '已掌握占比',
                  data.total == 0 ? '—' : '${data.masteredPercent}%',
                  '按当前手动标记',
                  width,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (data.total == 0)
          const _Panel(
            title: '暂无错题统计',
            subtitle: '添加错题后即可看到统计；也可以切换时间范围查看已有记录。',
            child: Icon(
              Icons.insights_outlined,
              size: 40,
              color: AppColors.mutedForeground,
            ),
          )
        else ...[
          if (!profile) ...[
            _Panel(
              title: '错题收录趋势',
              subtitle: '按收录日期统计，包含今天；收录增多不代表成绩退步。',
              child: _Trend(data: data),
            ),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _Panel(
                  title: '当前掌握情况',
                  subtitle: '所选错题的当前状态，不代表考试正确率。',
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 24,
                    runSpacing: 16,
                    children: [
                      Semantics(
                        label:
                            '当前掌握分布：${List.generate(3, (i) => '${labels[i]}${data.mastery[i]}道').join('，')}',
                        child: DonutChart(
                          slices: List.generate(
                            3,
                            (i) => DonutSlice(
                              value: data.mastery[i],
                              color: colors[i],
                              label: labels[i],
                            ),
                          ),
                          centerValue: data.total,
                          centerLabel: '道错题',
                          size: 140,
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: Column(
                          children: List.generate(
                            3,
                            (i) => TextButton(
                              onPressed: () => onShowQuestions(
                                labels[i],
                                data.questions
                                    .where(
                                      (q) =>
                                          WrongQuestionAnalytics.masteryOf(q) ==
                                          i,
                                    )
                                    .toList(),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.circle, color: colors[i], size: 9),
                                  const SizedBox(width: 8),
                                  Text(labels[i]),
                                  const Spacer(),
                                  Text('${data.mastery[i]} 道'),
                                  const Icon(Icons.chevron_right, size: 14),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _Panel(
                  title: '优先巩固的知识点',
                  subtitle: '仅统计未掌握和复习中的错题；同题同标签计一次，多标签可重复归属。点击查看题目。',
                  child: _Ranking(
                    counts: data.weakPoints,
                    color: AppColors.warning,
                    empty: '当前没有待巩固的错题',
                    onTap: (key) => onShowQuestions(
                      key,
                      data.questions
                          .where(
                            (q) =>
                                WrongQuestionAnalytics.masteryOf(q) != 2 &&
                                WrongQuestionAnalytics.knowledgeLabels(
                                  q,
                                ).contains(key),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ];
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [cards[0], const SizedBox(height: 16), cards[1]],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 16),
                  Expanded(child: cards[1]),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _Panel(
            title: profile ? '长期错题模块分布' : '本期错题模块分布',
            subtitle: '每道题按所属模块计一次；缺少模块的题目归入未分类。',
            child: _Ranking(
              counts: data.modules,
              color: AppColors.primary,
              onTap: (key) => onShowQuestions(
                key,
                data.questions
                    .where(
                      (q) =>
                          ((q.topic ?? '').trim().isEmpty
                              ? '未分类'
                              : q.topic!.trim()) ==
                          key,
                    )
                    .toList(),
              ),
            ),
          ),
          if (!profile) ...[
            const SizedBox(height: 16),
            _Panel(
              title: '已记录的错因',
              subtitle:
                  '${data.total} 道题中，${data.classifiedErrors} 道有结构化错因；其余归入未记录。分类来自 AI 诊断。',
              child: _Ranking(
                counts: data.errors,
                color: const Color(0xFF7C5CDB),
                onTap: (key) => onShowQuestions(
                  key,
                  data.questions
                      .where((q) => WrongQuestionAnalytics.errorType(q) == key)
                      .toList(),
                ),
              ),
            ),
          ],
        ],
        if (profile) ...[
          const SizedBox(height: 16),
          _Panel(
            title: '反复出现的错误',
            subtitle:
                '基于最近保留的 ${trace.length} 条诊断记录（最多 200 条）。次数指诊断记录数，同一道题可能多次出现。',
            child: recurring.isEmpty
                ? const Text(
                    '暂未发现重复错误，更多诊断记录会帮助完善画像。',
                    style: TextStyle(color: AppColors.mutedForeground),
                  )
                : Column(
                    children: recurring
                        .map(
                          (error) => ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              error.label,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '出现 ${error.records.length} 次 · 展开查看依据',
                            ),
                            children: error.records.map((record) {
                              final ts = record['ts'];
                              final date = ts is num && ts > 0
                                  ? DateTime.fromMillisecondsSinceEpoch(
                                      ts.toInt(),
                                    )
                                  : null;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${record['key_point'] ?? record['question'] ?? '暂无描述'}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${date == null ? '日期未记录' : '${date.year}/${date.month}/${date.day}'} · ${record['question'] ?? ''}',
                                ),
                              );
                            }).toList(),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ],
    );
  }

  Widget _metric(String title, String value, String note, double width) =>
      Container(
        width: width,
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.mutedForeground,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
              ),
            ),
            Text(
              note,
              style: const TextStyle(
                color: AppColors.mutedForeground,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Material(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.mutedForeground,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    ),
  );
}

class _Ranking extends StatelessWidget {
  const _Ranking({
    required this.counts,
    required this.color,
    required this.onTap,
    this.empty = '暂无数据',
  });
  final Map<String, int> counts;
  final Color color;
  final void Function(String) onTap;
  final String empty;
  @override
  Widget build(BuildContext context) {
    final ranked = WrongQuestionAnalytics.ranked(counts);
    if (ranked.isEmpty) return Text(empty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...ranked
            .take(6)
            .map(
              (entry) => Semantics(
                button: true,
                excludeSemantics: true,
                onTap: () => onTap(entry.key),
                label: '${entry.key}，${entry.value} 道，查看题目',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onTap(entry.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.key,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${entry.value} 道',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: AppColors.mutedForeground,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: entry.value / ranked.first.value,
                            minHeight: 6,
                            color: color,
                            backgroundColor: color.withValues(alpha: .09),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        if (ranked.length > 6)
          Text(
            '展示前 6 项，共 ${ranked.length} 项',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.mutedForeground,
            ),
          ),
      ],
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({required this.data});
  final WrongQuestionAnalytics data;
  @override
  Widget build(BuildContext context) {
    final points = data.daily;
    if (points.isEmpty) return const Text('请选择时间范围');
    final maximum = points.fold<int>(
      1,
      (max, e) => e.count > max ? e.count : max,
    );
    final step = (maximum / 4).ceilToDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: (maximum / step).ceil() * step + step,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: step,
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(
                points.length,
                (i) => BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: points[i].count.toDouble(),
                      width: points.length > 30
                          ? 3
                          : points.length > 7
                          ? 6
                          : 16,
                      color: AppColors.primary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: step,
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 ||
                          index >= points.length ||
                          (index != points.length - 1 &&
                              index % (points.length / 4).ceil() != 0)) {
                        return const SizedBox.shrink();
                      }
                      final date = points[index].date;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${date.month}/${date.day}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final point = points[group.x];
                    return BarTooltipItem(
                      '${point.date.month}/${point.date.day}\n${point.count} 道',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    );
                  },
                ),
              ),
            ),
            duration: AppMotion.resolve(context, AppMotion.counter),
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('查看每日明细', style: TextStyle(fontSize: 12)),
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: points
                  .map(
                    (p) => Text(
                      '${p.date.month}/${p.date.day}：${p.count} 道',
                      style: const TextStyle(fontSize: 12),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ],
    );
  }
}
