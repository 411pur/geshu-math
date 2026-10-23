import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/wrong_question_analytics.dart';
import '../providers/analytics_provider.dart';
import '../widgets/analytics_dashboard.dart';
import '../widgets/analytics_question_sheet.dart';
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
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.alarm, color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('定时报告设置', style: Theme.of(ctx).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ]),
                const SizedBox(height: 8),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用定时报告'),
                  subtitle: Text(draft.enabled ? '开启中 · ${draft.describe()}' : '当前未开启'),
                  value: draft.enabled,
                  onChanged: (v) => setSheetState(() => draft = ReportSchedule(
                    enabled: v, frequency: draft.frequency, weekday: draft.weekday,
                    intervalDays: draft.intervalDays, hour: draft.hour, minute: draft.minute,
                  )),
                ),

                const SizedBox(height: 8),
                const Text('发送频率', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'daily', label: Text('每天')),
                    ButtonSegment(value: 'weekly', label: Text('每周')),
                    ButtonSegment(value: 'interval', label: Text('每N天')),
                  ],
                  selected: {draft.frequency},
                  onSelectionChanged: (s) => setSheetState(() => draft = ReportSchedule(
                    enabled: draft.enabled, frequency: s.first, weekday: draft.weekday,
                    intervalDays: draft.intervalDays, hour: draft.hour, minute: draft.minute,
                  )),
                ),

                if (draft.frequency == 'weekly') ...[
                  const SizedBox(height: 12),
                  const Text('选择星期几', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, children: List.generate(7, (i) {
                    final wd = i + 1;
                    return ChoiceChip(
                      label: Text(ReportSchedule.weekdayCn(wd)),
                      selected: draft.weekday == wd,
                      onSelected: (_) => setSheetState(() => draft = ReportSchedule(
                        enabled: draft.enabled, frequency: draft.frequency, weekday: wd,
                        intervalDays: draft.intervalDays, hour: draft.hour, minute: draft.minute,
                      )),
                    );
                  })),
                ],

                if (draft.frequency == 'interval') ...[
                  const SizedBox(height: 12),
                  const Text('间隔天数', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, children: [3, 5, 7, 14].map((n) => ChoiceChip(
                    label: Text('$n天'),
                    selected: draft.intervalDays == n,
                    onSelected: (_) => setSheetState(() => draft = ReportSchedule(
                      enabled: draft.enabled, frequency: draft.frequency, weekday: draft.weekday,
                      intervalDays: n, hour: draft.hour, minute: draft.minute,
                    )),
                  )).toList()),
                ],

                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time),
                  title: const Text('发送时间'),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('${draft.hour.toString().padLeft(2, '0')}:${draft.minute.toString().padLeft(2, '0')}'),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(hour: draft.hour, minute: draft.minute),
                      );
                      if (t != null) {
                        setSheetState(() => draft = ReportSchedule(
                        enabled: draft.enabled, frequency: draft.frequency, weekday: draft.weekday,
                        intervalDays: draft.intervalDays, hour: t.hour, minute: t.minute,
                      ));
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
      appBar: AppBar(
        title: const Text('学习报告'),
        actions: [
          IconButton(
            icon: Stack(
              children: [
                Icon(_schedule.enabled ? Icons.alarm_on : Icons.alarm_add),
                if (_schedule.enabled)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: '定时设置',
            onPressed: _openScheduleSettings,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新生成',
            onPressed: _loading ? null : _generate,
          ),
        ],
        bottom: _schedule.enabled
            ? PreferredSize(
                preferredSize: const Size.fromHeight(36),
                child: Container(
                  width: double.infinity,
                  color: AppColors.accent.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.alarm,
                        size: 14,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '定时报告已开启 · ${_schedule.describe()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: _buildDashboard(),
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
    final data = WrongQuestionAnalytics(
      ref.watch(analyticsQuestionsProvider),
      now: DateTime.now(),
      days: _days,
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '错题学习报告',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text('从错题记录看清近期学习情况，再决定下一步复习重点。'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in [7, 30, 90])
              ChoiceChip(
                label: Text('近 $days 天'),
                selected: _days == days,
                onSelected: _loading
                    ? null
                    : (_) => setState(() => _days = days),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '统计范围：${data.daily.first.date.month}/${data.daily.first.date.day} — ${data.now.month}/${data.now.day} · 数据来源：当前错题本',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.mutedForeground,
          ),
        ),
        const SizedBox(height: 16),
        AnalyticsDashboard(
          data: data,
          onShowQuestions: (title, questions) =>
              showAnalyticsQuestions(context, title, questions),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            const Text(
              'AI 分析与复习建议',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            FilledButton.icon(
              onPressed: _loading || data.total == 0 ? null : () => _generate(),
              icon: const Icon(Icons.auto_awesome),
              label: Text(_loading ? '正在分析…' : '生成近 $_days 天报告'),
            ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (_reportError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _reportError!,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        if (_notEnoughData)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('所选时间内暂无错题，可扩大时间范围。'),
          ),
        if (_report.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _reportDays == null
                ? '已保存的历史报告 · 统计范围未记录，请重新生成以对齐图表。'
                : '上次生成：${_reportTime == null ? '时间未记录' : '${_reportTime!.year}/${_reportTime!.month}/${_reportTime!.day}'} · 近 $_reportDays 天；正文为生成时的快照，图表随错题本更新。',
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '上方统计无需 AI 即可查看。生成报告后，这里会展示分析和重点练习建议。',
              style: TextStyle(color: AppColors.mutedForeground),
            ),
          ),
        if (data.total == 0)
          TextButton(
            onPressed: () => context.go('/wrong-question/chat'),
            child: const Text('去添加错题'),
          ),
      ],
    );
  }
}
