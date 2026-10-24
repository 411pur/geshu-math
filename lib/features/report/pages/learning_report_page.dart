import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/wrong_question_analytics.dart';
import '../providers/analytics_provider.dart';
import '../providers/learning_memory_provider.dart';
import '../widgets/analytics_dashboard.dart';
import '../widgets/analytics_question_sheet.dart';
import '../widgets/learning_practice_page.dart';
import '../widgets/learning_report_summary_card.dart';
import '../../../domain/entities/wrong_question_entity.dart';
import '../../../shared/widgets/styled_markdown.dart';
import '../../../core/theme/app_colors.dart';
import '../services/report_scheduler.dart';
import '../services/report_generator.dart';

class LearningReportPage extends ConsumerStatefulWidget {
  const LearningReportPage({super.key});
  @override
  ConsumerState<LearningReportPage> createState() => _LearningReportPageState();
}

class _LearningReportPageState extends ConsumerState<LearningReportPage> {
  int _days = 7;
  int _view = 0;
  bool _loading = false;
  String _report = '';
  String? _reportError;
  int? _reportDays;
  DateTime? _reportTime;
  List<int> _recommendedIds = [];
  List<WrongQuestion> _recommended = []; // 解析出的推荐练习题目
  bool _notEnoughData = false;
  ReportSchedule _schedule = const ReportSchedule();
  bool _missedCheckDone = false;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule = ReportScheduleService.loadSchedule();
    // 打开页面：优先展示已生成/补发的最近报告
    final stored = ReportScheduleService.loadReportContent();
    if (stored != null && stored.isNotEmpty) {
      _report = stored;
      _reportDays = ReportScheduleService.loadReportDays();
      _reportTime = ReportScheduleService.loadReportTime();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _resolveRecommended(),
      );
      _recommendedIds = ReportScheduleService.loadRecommendedIds();
    }
    // 登录/进入页面时的补发检查：已过定时点且本周期未发 → 补生成
    if (ReportScheduleService.shouldTriggerMissed(_schedule, DateTime.now())) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkMissed());
    }
    // 页面开着时每 30 秒到点检查
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkSchedule(),
    );
  }

  bool _missedRunning = false;

  Future<void> _checkMissed() async {
    if (_missedCheckDone || _missedRunning || !mounted) return;
    _missedCheckDone = true;
    _missedRunning = true;
    ReportScheduleService.markSent(); // 先占位防重入，生成失败由手动触发兜底
    await _generate(auto: true);
    _missedRunning = false;
  }

  void _checkSchedule() {
    // 页面开着时的到点触发（分钟窗口）
    if (ReportScheduleService.isDueNow(_schedule, DateTime.now())) {
      ReportScheduleService.markSent();
      _generate(auto: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 解析推荐题目 id → 从错题库取出实体（供点击跳详情）。
  Future<void> _resolveRecommended() async {
    if (!mounted) return;
    if (_recommendedIds.isEmpty) {
      setState(() => _recommended = []);
      return;
    }
    try {
      final all = ref.read(analyticsQuestionsProvider);
      final byId = {for (final w in all) w.id: w};
      if (!mounted) return;
      setState(
        () => _recommended = _recommendedIds
            .map((id) => byId[id])
            .whereType<WrongQuestion>()
            .toList(),
      );
    } catch (_) {
      if (mounted) setState(() => _recommended = []);
    }
  }

  Future<void> _generate({bool auto = false}) async {
    if (_loading) return;
    final selectedDays = _days;
    setState(() {
      _loading = true;
      _reportError = null;
      _notEnoughData = false;
    });

    try {
      final result = await ReportGenerator.generate(ref, days: selectedDays);
      if (!mounted) return;
      if (result.content.trim().isEmpty) {
        setState(() {
          _loading = false;
          _notEnoughData = true;
        });
        if (auto && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('定时报告：近几天暂无错题数据，跳过生成')));
        }
        return;
      }
      ReportScheduleService.saveReportContent(
        result.content,
        days: selectedDays,
      );
      ReportScheduleService.saveRecommendedIds(result.recommendedIds);
      if (mounted) {
        setState(() {
          _report = result.content;
          _reportDays = selectedDays;
          _reportTime = ReportScheduleService.loadReportTime();
          _recommendedIds = result.recommendedIds;
          _loading = false;
        });
        await _resolveRecommended();
      }
      if (auto && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('📋 定时报告已生成')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _reportError = '报告生成失败，请检查网络和 AI 设置后重试。';
          _loading = false;
        });
      }
    }
  }

  // ── 定时设置弹窗（复用原逻辑，模型改由服务提供）────────────
  Future<void> _openScheduleSettings() async {
    var draft = _schedule;
    final result = await showModalBottomSheet<ReportSchedule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.alarm, color: Theme.of(ctx).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('定时报告设置', style: Theme.of(ctx).textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用定时报告'),
                  subtitle: Text(
                    draft.enabled ? '开启中 · ${draft.describe()}' : '当前未开启',
                  ),
                  value: draft.enabled,
                  onChanged: (v) => setSheetState(
                    () => draft = ReportSchedule(
                      enabled: v,
                      frequency: draft.frequency,
                      weekday: draft.weekday,
                      intervalDays: draft.intervalDays,
                      hour: draft.hour,
                      minute: draft.minute,
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                const Text(
                  '发送频率',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'daily', label: Text('每天')),
                    ButtonSegment(value: 'weekly', label: Text('每周')),
                    ButtonSegment(value: 'interval', label: Text('每N天')),
                  ],
                  selected: {draft.frequency},
                  onSelectionChanged: (s) => setSheetState(
                    () => draft = ReportSchedule(
                      enabled: draft.enabled,
                      frequency: s.first,
                      weekday: draft.weekday,
                      intervalDays: draft.intervalDays,
                      hour: draft.hour,
                      minute: draft.minute,
                    ),
                  ),
                ),

                if (draft.frequency == 'weekly') ...[
                  const SizedBox(height: 12),
                  const Text(
                    '选择星期几',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (i) {
                      final wd = i + 1;
                      return ChoiceChip(
                        label: Text(ReportSchedule.weekdayCn(wd)),
                        selected: draft.weekday == wd,
                        onSelected: (_) => setSheetState(
                          () => draft = ReportSchedule(
                            enabled: draft.enabled,
                            frequency: draft.frequency,
                            weekday: wd,
                            intervalDays: draft.intervalDays,
                            hour: draft.hour,
                            minute: draft.minute,
                          ),
                        ),
                      );
                    }),
                  ),
                ],

                if (draft.frequency == 'interval') ...[
                  const SizedBox(height: 12),
                  const Text(
                    '间隔天数',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [3, 5, 7, 14]
                        .map(
                          (n) => ChoiceChip(
                            label: Text('$n天'),
                            selected: draft.intervalDays == n,
                            onSelected: (_) => setSheetState(
                              () => draft = ReportSchedule(
                                enabled: draft.enabled,
                                frequency: draft.frequency,
                                weekday: draft.weekday,
                                intervalDays: n,
                                hour: draft.hour,
                                minute: draft.minute,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],

                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time),
                  title: const Text('发送时间'),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(
                      '${draft.hour.toString().padLeft(2, '0')}:${draft.minute.toString().padLeft(2, '0')}',
                    ),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(
                          hour: draft.hour,
                          minute: draft.minute,
                        ),
                      );
                      if (t != null) {
                        setSheetState(
                          () => draft = ReportSchedule(
                            enabled: draft.enabled,
                            frequency: draft.frequency,
                            weekday: draft.weekday,
                            intervalDays: draft.intervalDays,
                            hour: t.hour,
                            minute: t.minute,
                          ),
                        );
                      }
                    },
                  ),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, draft),
                    child: const Text('保存设置'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != null) {
      _schedule = result;
      ReportScheduleService.saveSchedule(result);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: _buildDashboard()),
    );
  }

  /// 报告视图：彩色 Markdown 正文 + 重点练习建议卡片 + 去错题本入口。
  Widget _buildReportView() {
    // 去掉报告的「推荐练习」尾行（由下方卡片展示），避免正文出现残留行
    final body = _report.replaceFirst(
      RegExp(r'【推荐练习】\s*题目ID\s*[:：]\s*[^\n]*\n?'),
      '',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StyledMarkdown(data: body, fontSize: 14.5),
        if (_recommended.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.track_changes, size: 18, color: AppColors.error),
              SizedBox(width: 6),
              Text(
                '重点练习建议',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'AI 建议优先补强的题目，点击可查看原题与讲解',
            style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
          ),
          const SizedBox(height: 8),
          for (final w in _recommended) _recommendCard(w),
        ],
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.book_outlined),
            label: const Text('去错题本查看全部'),
            onPressed: () => context.go('/wrong-question/list'),
          ),
        ),
      ],
    );
  }

  Widget _recommendCard(WrongQuestion w) {
    final topic = (w.topic != null && w.topic!.isNotEmpty)
        ? w.topic!
        : (w.subTopic != null && w.subTopic!.isNotEmpty ? w.subTopic! : '数学');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.flag_circle, color: AppColors.error),
        title: Text(
          w.questionText.length > 36
              ? '${w.questionText.substring(0, 36)}…'
              : w.questionText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          topic,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.mutedForeground,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          size: 20,
          color: AppColors.border,
        ),
        onTap: () => openAnalyticsQuestion(context, ref, w),
      ),
    );
  }

  Widget _buildDashboard() {
    final questions = ref.watch(analyticsQuestionsProvider);
    final now = DateTime.now();
    final data = WrongQuestionAnalytics(questions, now: now, days: _days);
    final nextSuggestion = suggestPractice(
      questions,
      ref.watch(learningMemoryProvider),
      now,
    ).firstOrNull;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final horizontal = wide ? 28.0 : 16.0;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 24),
              children: [
                _toolbar(data),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: KeyedSubtree(
                    key: ValueKey<int>(_view),
                    child: switch (_view) {
                      0 => _overview(data, nextSuggestion, wide),
                      1 => _dataView(data),
                      _ => _reportView(data),
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _toolbar(WrongQuestionAnalytics data) {
    final title = switch (_view) {
      1 => '数据统计',
      2 => '学习报告',
      _ => '学习概览',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (_view != 0) ...[
              IconButton(
                tooltip: '返回学习概览',
                onPressed: () => setState(() => _view = 0),
                icon: const Icon(Icons.arrow_back, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 2),
            ] else ...[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.insights_outlined,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            IconButton(
              tooltip: '定时设置',
              onPressed: _openScheduleSettings,
              icon: Stack(
                children: [
                  Icon(_schedule.enabled ? Icons.alarm_on : Icons.alarm_add),
                  if (_schedule.enabled)
                    const Positioned(
                      right: 1,
                      top: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox(width: 7, height: 7),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: '重新生成报告',
              onPressed: _loading || data.total == 0 ? null : () => _generate(),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_schedule.enabled) ...[
          const SizedBox(height: 6),
          Text(
            '定时报告已开启 · ${_schedule.describe()}',
            style: const TextStyle(fontSize: 12, color: AppColors.accent),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final days in [7, 30, 90])
              ChoiceChip(
                label: Text('近 $days 天'),
                selected: _days == days,
                visualDensity: VisualDensity.compact,
                onSelected: _loading
                    ? null
                    : (_) => setState(() => _days = days),
              ),
            Text(
              _periodLabel(data),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }

  Widget _overview(
    WrongQuestionAnalytics data,
    LearningSuggestion? nextSuggestion,
    bool wide,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LearningReportSummaryCard(
          data: data,
          days: _days,
          nextSuggestion: nextSuggestion,
          onPractice: nextSuggestion == null
              ? null
              : () => openLearningPractice(context, nextSuggestion),
          onAddQuestion: () => context.go('/wrong-question/chat'),
        ),
        const SizedBox(height: 16),
        _quickActions(wide),
      ],
    );
  }

  Widget _quickActions(bool wide) {
    final cards = [
      _QuickActionCard(
        icon: Icons.query_stats,
        title: '数据统计',
        subtitle: '趋势、掌握度与错因结构',
        onTap: () => setState(() => _view = 1),
      ),
      _QuickActionCard(
        icon: Icons.description_outlined,
        title: '学习报告',
        subtitle: '生成并回看阶段分析',
        onTap: () => setState(() => _view = 2),
      ),
      _QuickActionCard(
        icon: Icons.account_circle_outlined,
        title: '学生画像',
        subtitle: '长期薄弱点与学习节奏',
        onTap: () => context.go('/profile/portrait'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('快捷入口', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Text('常用功能', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 10),
        if (wide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < cards.length; index++) ...[
                  Expanded(child: cards[index]),
                  if (index != cards.length - 1) const SizedBox(width: 12),
                ],
              ],
            ),
          )
        else
          Column(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                cards[index],
                if (index != cards.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
      ],
    );
  }

  Widget _dataView(WrongQuestionAnalytics data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_periodLabel(data), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        AnalyticsDashboard(
          data: data,
          onShowQuestions: (title, questions) =>
              showAnalyticsQuestions(context, title, questions),
        ),
      ],
    );
  }

  Widget _reportView(WrongQuestionAnalytics data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI 学习报告',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '基于近 $_days 天错题本生成',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: _loading || data.total == 0
                        ? null
                        : () => _generate(),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(_loading ? '正在分析…' : '生成报告'),
                  ),
                ],
              ),
              if (_loading) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
              ],
              if (_reportError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _reportError!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],
              if (_notEnoughData) ...[
                const SizedBox(height: 10),
                Text(
                  '所选时间内暂无错题，可扩大时间范围。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_report.isNotEmpty) ...[
          Text(
            _reportDays == null
                ? '已保存的历史报告 · 统计范围未记录，请重新生成以对齐图表。'
                : '上次生成：${_reportTime == null ? '时间未记录' : '${_reportTime!.year}/${_reportTime!.month}/${_reportTime!.day}'} · 近 $_reportDays 天',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.mutedForeground,
            ),
          ),
          if (_reportDays != _days)
            const Text(
              '当前图表范围与已保存报告不同，可重新生成报告。',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          const SizedBox(height: 16),
          _buildReportView(),
        ] else if (!_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              '生成报告后，这里会展示数学分析和重点练习建议。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  String _periodLabel(WrongQuestionAnalytics data) {
    if (data.daily.isEmpty) return '统计范围：—';
    final start = data.daily.first.date;
    final end = data.now;
    String two(int value) => value.toString().padLeft(2, '0');
    return '统计范围：${start.year}.${two(start.month)}.${two(start.day)} — '
        '${end.year}.${two(end.month)}.${two(end.day)} · 当前错题本';
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward,
                size: 18,
                color: AppColors.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
