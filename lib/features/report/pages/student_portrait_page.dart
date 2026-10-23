import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/styled_markdown.dart';
import '../../home/providers/student_insight_provider.dart';
import '../../home/providers/student_profile_provider.dart';
import '../models/portrait_summary.dart';
import '../models/wrong_question_analytics.dart';
import '../providers/analytics_provider.dart';
import '../services/portrait_generator.dart';
import '../services/portrait_store.dart';
import '../widgets/analytics_dashboard.dart';
import '../widgets/analytics_question_sheet.dart';

/// 学生画像：长期错题统计 + 学习节奏 + 反复错误 + 自述薄弱点 + AI 解读。
///
/// 与「学习报告」的区别：报告按 7/30/90 天看阶段表现，画像固定看全量数据，
/// 关注「这个学生长期是什么样、下一步该先补什么」。
class StudentPortraitPage extends ConsumerStatefulWidget {
  const StudentPortraitPage({super.key});

  @override
  ConsumerState<StudentPortraitPage> createState() =>
      _StudentPortraitPageState();
}

class _StudentPortraitPageState extends ConsumerState<StudentPortraitPage> {
  final _weakController = TextEditingController();
  PortraitCache? _cache;
  bool _aiLoading = false;
  String? _aiError;
  bool _weakDirty = false;

  @override
  void initState() {
    super.initState();
    _cache = PortraitStore.load();
    _weakController.text = ref.read(studentInsightProvider).manualWeakPoints;
  }

  @override
  void dispose() {
    _weakController.dispose();
    super.dispose();
  }

  Future<void> _generateAi(PortraitSummary summary) async {
    if (_aiLoading || summary.total == 0) return;
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });
    try {
      final insight = ref.read(studentInsightProvider);
      final profile = ref.read(studentProfileProvider);
      final content = await PortraitGenerator.generate(
        ref,
        summary: summary,
        trace: insight.errorTrace,
        manualWeakPoints: _weakController.text,
        name: profile.name,
      );
      if (!mounted) return;
      if (content.isEmpty) {
        setState(() {
          _aiLoading = false;
          _aiError = '模型没有返回内容，请稍后重试。';
        });
        return;
      }
      PortraitStore.save(content: content, total: summary.total);
      setState(() {
        _cache = PortraitCache(
          content: content,
          generatedAt: DateTime.now().millisecondsSinceEpoch,
          total: summary.total,
        );
        _aiLoading = false;
      });
    } on AiApiException catch (e) {
      if (mounted) {
        setState(() {
          _aiLoading = false;
          _aiError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _aiLoading = false;
          _aiError = '画像生成失败，请检查网络与 AI 设置后重试。';
        });
      }
    }
  }

  void _saveWeakPoints() {
    ref
        .read(studentInsightProvider.notifier)
        .setManualWeakPoints(_weakController.text);
    setState(() => _weakDirty = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存自述薄弱点，之后讲解会参考它')));
  }

  @override
  Widget build(BuildContext context) {
    final questions = ref.watch(analyticsQuestionsProvider);
    final insight = ref.watch(studentInsightProvider);
    final profile = ref.watch(studentProfileProvider);
    final now = DateTime.now();
    final summary = PortraitSummary.from(questions, now: now);
    final analytics = WrongQuestionAnalytics(questions, now: now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('学生画像'),
        actions: [
          IconButton(
            tooltip: '重新生成 AI 解读',
            icon: const Icon(Icons.auto_awesome),
            onPressed: _aiLoading || summary.total == 0
                ? null
                : () => _generateAi(summary),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _HeroCard(
            name: profile.name.trim().isEmpty ? '同学' : profile.name.trim(),
            avatarBase64: profile.avatarBase64,
            headline: summary.headline,
            streakDays: summary.streakDays,
            onOpenReport: () => context.go('/profile/report'),
          ),
          const SizedBox(height: 16),
          if (summary.total == 0) ...[
            _Panel(
              title: '还没有可分析的错题',
              subtitle: '画像完全来自你的错题本：先添加一道错题，统计、薄弱点和 AI 解读才会出现。',
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => context.go('/wrong-question/chat'),
                  icon: const Icon(Icons.add),
                  label: const Text('去添加错题'),
                ),
              ),
            ),
          ] else ...[
            _KpiGrid(summary: summary),
            const SizedBox(height: 16),
            _RhythmPanel(summary: summary),
            const SizedBox(height: 16),
            AnalyticsDashboard(
              data: analytics,
              profile: true,
              trace: insight.errorTrace,
              onShowQuestions: (title, list) =>
                  showAnalyticsQuestions(context, title, list),
            ),
            const SizedBox(height: 16),
            _ErrorTypePanel(summary: summary),
            const SizedBox(height: 16),
            _WeakPointsPanel(
              controller: _weakController,
              dirty: _weakDirty,
              onChanged: (v) {
                if (!_weakDirty && v != insight.manualWeakPoints) {
                  setState(() => _weakDirty = true);
                }
              },
              onSave: _saveWeakPoints,
            ),
            const SizedBox(height: 16),
            _AiPanel(
              cache: _cache,
              loading: _aiLoading,
              error: _aiError,
              total: summary.total,
              onGenerate: () => _generateAi(summary),
            ),
            const SizedBox(height: 16),
            _TracePanel(trace: insight.errorTrace),
          ],
        ],
      ),
    );
  }
}

// ── 顶部名片 ────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.name,
    required this.avatarBase64,
    required this.headline,
    required this.streakDays,
    required this.onOpenReport,
  });

  final String name;
  final String avatarBase64;
  final String headline;
  final int streakDays;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final bytes = avatarBase64.isEmpty
        ? null
        : _base64DecodeOrNull(avatarBase64);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.10),
            AppColors.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                backgroundImage: bytes == null ? null : MemoryImage(bytes),
                child: bytes != null
                    ? null
                    : const Icon(
                        Icons.person,
                        size: 32,
                        color: AppColors.primary,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headline,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (streakDays > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department,
                        size: 15,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '连续 $streakDays 天',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onOpenReport,
              icon: const Icon(Icons.assessment_outlined, size: 16),
              label: const Text('查看阶段学习报告'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 容错解码头像：非法 base64 时返回 null，避免整页崩溃。
Uint8List? _base64DecodeOrNull(String dataUri) {
  try {
    final raw = dataUri.contains(',') ? dataUri.split(',').last : dataUri;
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

// ── KPI ────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary});

  final PortraitSummary summary;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('累计错题', '${summary.total}', '道', AppColors.primary),
      ('本周新增', '${summary.weekNew}', '道', AppColors.warning),
      (
        '掌握率',
        '${summary.masteredPercent}%',
        '${summary.pending} 道待巩固',
        AppColors.accent,
      ),
      ('累计复习', '${summary.reviewTotal}', '次', AppColors.functions),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value, note, color) in items)
              Container(
                width: width,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          note,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── 学习节奏（近 8 周）────────────────────────────────────────────────

class _RhythmPanel extends StatelessWidget {
  const _RhythmPanel({required this.summary});

  final PortraitSummary summary;

  @override
  Widget build(BuildContext context) {
    final weeks = summary.weekly;
    final maxCount = weeks.fold<int>(0, (m, w) => w.count > m ? w.count : m);
    return _Panel(
      title: '学习节奏',
      subtitle:
          '近 8 周每周新增错题；近 30 天有 ${summary.activeDays30} 天在记录。'
          '错题变多可能是复习强度提高，不等同于退步。',
      child: SizedBox(
        height: 96,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < weeks.length; i++)
              Expanded(
                child: _WeekBar(
                  week: weeks[i],
                  ratio: maxCount == 0 ? 0 : weeks[i].count / maxCount,
                  highlight: i == weeks.length - 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.week,
    required this.ratio,
    required this.highlight,
  });

  final PortraitWeek week;
  final double ratio;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${week.label} 起的一周，新增 ${week.count} 道错题',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            week.count == 0 ? '' : '${week.count}',
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 14,
            height: 8 + 52 * ratio,
            decoration: BoxDecoration(
              color: highlight
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            week.label,
            style: const TextStyle(
              fontSize: 9.5,
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 错因分布 ──────────────────────────────────────────────────────────

class _ErrorTypePanel extends StatelessWidget {
  const _ErrorTypePanel({required this.summary});

  final PortraitSummary summary;

  @override
  Widget build(BuildContext context) {
    final rows = summary.errorTypes;
    final maxCount = rows.fold<int>(0, (m, e) => e.value > m ? e.value : m);
    return _Panel(
      title: '错因分布',
      subtitle: '来自 AI 诊断的结构化错因；「未记录」是还没做过结构化诊断的题，不能推断原因。',
      child: rows.isEmpty
          ? const Text(
              '还没有错因记录。',
              style: TextStyle(color: AppColors.mutedForeground),
            )
          : Column(
              children: [
                for (final e in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 68,
                          child: Text(
                            e.key,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxCount == 0 ? 0 : e.value / maxCount,
                              minHeight: 8,
                              backgroundColor: AppColors.secondarySystem,
                              color: e.key == '未记录'
                                  ? AppColors.border
                                  : const Color(0xFF7C5CDB),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${e.value}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── 自述薄弱点 ────────────────────────────────────────────────────────

class _WeakPointsPanel extends StatelessWidget {
  const _WeakPointsPanel({
    required this.controller,
    required this.dirty,
    required this.onChanged,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool dirty;
  final ValueChanged<String> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '自述薄弱点',
      subtitle: '写下令你自己头疼的地方（章节、题型、习惯都行）。它会随画像一起送给 AI，讲解时更有针对性。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            onChanged: onChanged,
            decoration: const InputDecoration(
              hintText: '例如：立体几何辅助线不会做；二次函数最值容易漏定义域',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: dirty ? onSave : null,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

// ── AI 解读 ───────────────────────────────────────────────────────────

class _AiPanel extends StatelessWidget {
  const _AiPanel({
    required this.cache,
    required this.loading,
    required this.error,
    required this.total,
    required this.onGenerate,
  });

  final PortraitCache? cache;
  final bool loading;
  final String? error;
  final int total;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final cache = this.cache;
    return _Panel(
      title: 'AI 画像解读',
      subtitle: '基于统计与最近错误点生成，不会编造分数或排名；仅供参考，不替代老师判断。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              '正在分析错题数据…',
              style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
            ),
          ] else if (cache != null) ...[
            StyledMarkdown(data: cache.content, fontSize: 14),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '生成于 ${_fmtDate(cache.time)} · 基于 $total 道错题',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onGenerate,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重新生成'),
                ),
              ],
            ),
          ] else ...[
            const Text(
              '生成一段画像解读：一句话画像、学习状态、优势、待突破，以及 3 条可执行的下一步行动。',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: total == 0 ? null : onGenerate,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('生成画像解读'),
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: const TextStyle(color: AppColors.error, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 最近诊断记录 ──────────────────────────────────────────────────────

class _TracePanel extends StatelessWidget {
  const _TracePanel({required this.trace});

  final List<Map<String, dynamic>> trace;

  @override
  Widget build(BuildContext context) {
    final recent = trace.reversed.take(8).toList();
    return _Panel(
      title: '最近诊断记录',
      subtitle: trace.isEmpty
          ? '每次 AI 讲解都会把「具体错误点」记在这里，用于发现反复出现的同类问题。'
          : '共 ${trace.length} 条，展示最近 ${recent.length} 条；同一道题多次诊断会分别记录。',
      child: recent.isEmpty
          ? const Text(
              '还没有诊断记录，去错题指导里讲一道题吧。',
              style: TextStyle(color: AppColors.mutedForeground),
            )
          : Column(children: [for (final e in recent) _TraceTile(entry: e)]),
    );
  }
}

class _TraceTile extends StatelessWidget {
  const _TraceTile({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final ts = entry['ts'];
    final date = ts is num && ts > 0
        ? DateTime.fromMillisecondsSinceEpoch(ts.toInt())
        : null;
    final errorType = (entry['error_type'] ?? '').toString();
    final keyPoint = (entry['key_point'] ?? '').toString();
    final question = (entry['question'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      date == null ? '日期未记录' : _fmtDate(date),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    if (errorType.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          errorType,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (keyPoint.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    keyPoint,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.foreground,
                    ),
                  ),
                ],
                if (question.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    question,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 通用容器 ──────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

String _fmtDate(DateTime d) => '${d.year}/${d.month}/${d.day}';
