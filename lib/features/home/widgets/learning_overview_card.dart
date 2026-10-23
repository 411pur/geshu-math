import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/app_motion.dart';
import '../../../domain/entities/wrong_question_entity.dart';
import 'donut_chart.dart';
import 'expandable_stack.dart';

/// 「学习情况」合并卡：左边是掌握度数据，右边直接是最近错题。
///
/// 设计意图是把原来两块内容压成一条线：**总量 → 分布 → 具体记录**。
/// 环上的分段和图例都可以点，点了右边就只显示那一类的错题，
/// 让统计图不只是好看，而是能直接用来筛选。
class LearningOverviewCard extends StatefulWidget {
  const LearningOverviewCard({
    super.key,
    required this.total,
    required this.mastered,
    required this.reviewing,
    required this.untouched,
    required this.newThisWeek,
    required this.examCount,
    required this.averageScore,
    required this.weakPoints,
    required this.questions,
    required this.onOpenQuestion,
    required this.onViewAll,
    this.recentLimit = 3,
    this.embedded = false,
  });

  /// 为 true 时不自带卡片底色 / 内边距，交给外层容器统一提供，
  /// 便于和「学习工具」拼成一块整体面板。
  final bool embedded;

  final int total;
  final int mastered;
  final int reviewing;
  final int untouched;
  final int newThisWeek;
  final int examCount;
  final double? averageScore;

  /// 从错题 topic / tags 聚合出的薄弱知识点（已按出现次数排序）。
  final List<String> weakPoints;

  /// 全部错题（按时间倒序），卡内自行按筛选条件取前几条。
  final List<WrongQuestion> questions;

  final void Function(WrongQuestion item) onOpenQuestion;
  final VoidCallback onViewAll;
  final int recentLimit;

  @override
  State<LearningOverviewCard> createState() => _LearningOverviewCardState();
}

class _LearningOverviewCardState extends State<LearningOverviewCard> {
  /// 0 = 已掌握，1 = 复习中，2 = 未掌握，null = 全部。
  int? _masteryFilter;
  bool _showSources = false;

  static const double _donutSize = 116;

  // 顺序严格对应 mastery 字段：0 = 未掌握，1 = 复习中，2 = 已掌握。
  // 图例、色块、环上分段、筛选条件共用同一套下标，避免对错。
  static const _colors = [
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFF34C759),
  ];
  static const _labels = ['未掌握', '复习中', '已掌握'];

  List<int> get _counts => [
    widget.untouched,
    widget.reviewing,
    widget.mastered,
  ];

  List<WrongQuestion> get _visibleQuestions {
    final filter = _masteryFilter;
    final list = filter == null
        ? widget.questions
        : widget.questions.where((q) => q.mastery == filter).toList();
    return list.take(widget.recentLimit).toList();
  }

  void _selectMastery(int? value) {
    setState(() => _masteryFilter = _masteryFilter == value ? null : value);
  }

  /// 点击圆环时按角度判断落在哪一段上。
  void _onDonutTapDown(TapDownDetails details) {
    final sum = _counts.fold<int>(0, (a, b) => a + b);
    if (sum <= 0) return;

    final local = details.localPosition;
    final offset = Offset(local.dx - _donutSize / 2, local.dy - _donutSize / 2);
    // 0 弧度对应 12 点方向（环从正上方开始画）
    var angle = math.atan2(offset.dy, offset.dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    var start = 0.0;
    for (var i = 0; i < 3; i++) {
      final sweep = (_counts[i] / sum) * 2 * math.pi;
      if (angle >= start && angle < start + sweep) {
        _selectMastery(i);
        return;
      }
      start += sweep;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        // 宽屏：环 | 统计 | 错题 三栏；窄屏：上下排布
        final wide = constraints.maxWidth >= 880;
        final stats = _statsColumn(context);
        final questions = _questionsColumn(context);

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _donut(context),
                  const SizedBox(width: 20),
                  Expanded(child: stats),
                ],
              ),
              const SizedBox(height: 20),
              questions,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _donut(context),
            const SizedBox(width: 22),
            Expanded(flex: 4, child: stats),
            const SizedBox(width: 22),
            Expanded(flex: 5, child: questions),
          ],
        );
      },
    );

    if (widget.embedded) return content;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _surface(),
      child: content,
    );
  }

  Widget _donut(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _showSources = true),
      onExit: (_) => setState(() => _showSources = false),
      child: GestureDetector(
        onTapDown: _onDonutTapDown,
        child: DonutChart(
          size: _donutSize,
          slices: [
            DonutSlice(
              value: widget.untouched,
              color: _colors[0],
              label: '未掌握',
            ),
            DonutSlice(
              value: widget.reviewing,
              color: _colors[1],
              label: '复习中',
            ),
            DonutSlice(value: widget.mastered, color: _colors[2], label: '已掌握'),
          ],
          centerValue: widget.total,
          centerLabel: '错题总数',
        ),
      ),
    );
  }

  Widget _statsColumn(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, AppMotion.standard),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      child: _showSources
          ? _sourcesPanel(key: const ValueKey('sources'))
          : _legendPanel(key: const ValueKey('legend')),
    );
  }

  Widget _legendPanel({required Key key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _masteryFilter == null
              ? '共 ${widget.total} 道错题'
              : '${_labels[_masteryFilter!]} · ${_counts[_masteryFilter!]} 道',
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1D1D1F),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _masteryRow(i),
        ],
        const SizedBox(height: 10),
        Text(
          '本周新增 ${widget.newThisWeek} · 考试均分 '
          '${widget.averageScore?.toStringAsFixed(0) ?? '—'}',
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF6E6E73)),
        ),
        if (widget.weakPoints.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '薄弱：${widget.weakPoints.join(' · ')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: const Color(0xFFFF3B30).withValues(alpha: 0.75),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          '点环或色块筛选右侧错题',
          style: TextStyle(
            fontSize: 10.5,
            color: const Color(0xFF1D1D1F).withValues(alpha: 0.32),
          ),
        ),
      ],
    );
  }

  Widget _masteryRow(int index) {
    final selected = _masteryFilter == index;
    return AppPressScale(
      key: ValueKey('masteryRow$index'),
      pressedScale: 0.96,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectMastery(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? _colors[index].withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.zero,
            border: Border.fromBorderSide(
              BorderSide(
                color: selected
                    ? _colors[index].withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(width: 10, height: 10, color: _colors[index]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _labels[index],
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: const Color(0xFF1D1D1F),
                  ),
                ),
              ),
              AppCountUp(
                value: _counts[index],
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1D1D1F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionsColumn(BuildContext context) {
    final list = _visibleQuestions;
    final filtered = _masteryFilter != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              filtered ? '${_labels[_masteryFilter!]}错题' : '最近错题',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D1D1F),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: widget.onViewAll,
              style: TextButton.styleFrom(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '查看全部',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF007AFF)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (list.isEmpty)
          Container(
            height: 116,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFF7F9FD),
              borderRadius: BorderRadius.zero,
            ),
            child: Text(
              filtered ? '这一类暂时没有错题' : '还没有错题，去做一道题吧',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73)),
            ),
          )
        else
          ExpandableStack(
            itemCount: list.length,
            cardHeight: 116,
            peek: 13,
            onCardTap: (index) => widget.onOpenQuestion(list[index]),
            cardBuilder: (context, index, isFront) =>
                _questionCard(list[index], isFront),
          ),
      ],
    );
  }

  Widget _questionCard(WrongQuestion item, bool isFront) {
    final mastery = item.mastery.clamp(0, 2);
    final color = _colors[mastery];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.fromBorderSide(
          BorderSide(
            color: isFront ? color.withValues(alpha: 0.55) : _hairline,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 24,
            offset: Offset(0, 10),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                color: color.withValues(alpha: 0.12),
                child: Text(
                  _labels[mastery],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const Spacer(),
              if (item.topic != null)
                Text(
                  item.topic!,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF6E6E73),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.questionText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D1D1F),
            ),
          ),
        ],
      ),
    );
  }

  /// 悬停圆环时替换掉左边的统计，逐条说明数字来源。
  Widget _sourcesPanel({required Key key}) {
    final avg = widget.averageScore;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(width: 3, height: 13, color: const Color(0xFF007AFF)),
            const SizedBox(width: 7),
            const Text(
              '数据来源',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D1D1F),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _sourceItem('错题总数', '${widget.total}', '本地错题本全部记录'),
        const SizedBox(height: 8),
        _sourceItem(
          '掌握度',
          '${widget.mastered} / ${widget.reviewing} / ${widget.untouched}',
          '按错题的掌握度字段分组',
        ),
        const SizedBox(height: 8),
        _sourceItem('本周新增', '${widget.newThisWeek}', '近 7 天创建的错题'),
        const SizedBox(height: 8),
        _sourceItem(
          '考试均分',
          avg == null ? '—' : avg.toStringAsFixed(0),
          widget.examCount > 0 ? '${widget.examCount} 次考试记录' : '还没有考试记录',
        ),
        const SizedBox(height: 8),
        Text(
          '全部为本地统计，不上传',
          style: TextStyle(
            fontSize: 10,
            color: const Color(0xFF1D1D1F).withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }

  Widget _sourceItem(String label, String value, String source) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73)),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1D1D1F),
            ),
          ),
        ),
        Expanded(
          child: Text(
            source,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: const Color(0xFF1D1D1F).withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }

  static const Color _hairline = Color(0x140F172A);

  BoxDecoration _surface() => const BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.zero,
    border: Border.fromBorderSide(BorderSide(color: _hairline)),
    boxShadow: [
      BoxShadow(color: Color(0x0F0F172A), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x140F172A),
        blurRadius: 24,
        offset: Offset(0, 10),
        spreadRadius: -12,
      ),
    ],
  );
}
