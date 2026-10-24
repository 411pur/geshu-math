import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../lesson_studio/data/lesson_ai_config.dart';
import '../../report/models/wrong_question_analytics.dart';
import '../../report/providers/analytics_provider.dart';
import '../../report/widgets/analytics_dashboard.dart';
import '../../report/widgets/analytics_question_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/ai_settings_provider.dart';
import '../providers/student_insight_provider.dart';

/// 设置页：查看 / 修改各板块的 AI 配置（URL / API Key / 模型 / 提示词）。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  final _reasoningModel = TextEditingController();
  final _visionModel = TextEditingController();
  final _weakPointsController = TextEditingController();

  // 板块配置表单
  late final Map<String, _BoardForm> _boards = {
    'wrongQuestion': _BoardForm('错题指导'),
    'exam': _BoardForm('考试分析'),
    'qa': _BoardForm('智能问答'),
    'report': _BoardForm('学习报告'),
    'lesson': _BoardForm('互动讲解'),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFromState();
      _weakPointsController.text = ref
          .read(studentInsightProvider)
          .manualWeakPoints;
    });
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _reasoningModel.dispose();
    _visionModel.dispose();
    _weakPointsController.dispose();
    for (final b in _boards.values) {
      b.dispose();
    }
    super.dispose();
  }

  void _loadFromState() {
    final s = ref.read(aiSettingsProvider);
    _baseUrl.text = s.baseUrl;
    _apiKey.text = s.apiKey;
    _model.text = s.model;
    _reasoningModel.text = s.reasoningModel;
    _visionModel.text = s.visionModel;
    _boards['wrongQuestion']!.load(s.wrongQuestion);
    _boards['exam']!.load(s.exam);
    _boards['qa']!.load(s.qa);
    _boards['report']!.load(s.report);
    _boards['lesson']!.load(s.lesson);
  }

  bool _testing = false;
  String _connection = '';
  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _connection = '正在检测快速、推理与视觉模型…';
    });
    try {
      final response =
          await Dio(
            BaseOptions(receiveTimeout: const Duration(seconds: 75)),
          ).post<Map<String, dynamic>>(
            '${LessonAiConfig.externalLessonBridgeUrl}/api/ai/test',
            data: const <String, dynamic>{},
            options: Options(contentType: Headers.jsonContentType),
          );
      final data = response.data ?? const <String, dynamic>{};
      final roles = (data['roles'] as List?) ?? const [];
      final details = roles
          .map((raw) {
            final item = raw is Map ? raw : const <String, dynamic>{};
            final ok = item['ok'] == true;
            final latency = item['latencyMs'];
            final provider = item['provider']?.toString() ?? '';
            final model = item['model']?.toString() ?? '';
            final label =
                item['label']?.toString() ?? item['role']?.toString() ?? '模型';
            final suffix = latency is num ? ' · ${latency}ms' : '';
            final reason = ok ? '' : '\n  ${item['message'] ?? '不可用'}';
            return '${ok ? '✓' : '×'} $label · $provider / $model$suffix$reason';
          })
          .join('\n');
      final summary = data['message']?.toString() ?? '模型检测完成';
      if (mounted) {
        setState(
          () => _connection = details.isEmpty ? summary : '$summary\n$details',
        );
      }
    } on DioException catch (error) {
      final payload = error.response?.data;
      if (mounted) {
        setState(
          () => _connection = payload is Map
              ? (payload['message'] ?? '连接失败').toString()
              : '服务不可用，请确认「启动项目.bat」窗口仍在运行',
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _save() {
    for (final value in [
      _baseUrl.text,
      ..._boards.values.map((b) => b.url.text),
    ]) {
      if (value.trim().isEmpty) continue;
      final uri = Uri.tryParse(value.trim());
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请填写有效的 HTTP(S) 地址')));
        return;
      }
    }
    final notifier = ref.read(aiSettingsProvider.notifier);
    notifier.saveGlobal(
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim(),
      reasoningModel: _reasoningModel.text.trim(),
      visionModel: _visionModel.text.trim(),
    );
    for (final entry in _boards.entries) {
      notifier.saveBoard(entry.key, entry.value.toConfig());
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存设置')));
  }

  void _resetAll() {
    ref.read(aiSettingsProvider.notifier).reset();
    _loadFromState();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已恢复默认配置')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(
            '全局配置',
            ApiEndpoints.managedAi
                ? '当前来源：根目录 local.config.json；密钥由服务端 .env.local 管理。修改后重启生效。'
                : '配置文件提供默认值；浏览器仅保存个人覆盖，留空跟随默认',
          ),
          if (ApiEndpoints.managedAi) ...[
            Text(
              '服务地址：${ApiEndpoints.baseUrl}\n快速/结构化：${ApiEndpoints.model}\n高难推理：${ApiEndpoints.reasoningModel}\n图片理解：${ApiEndpoints.visionModel}',
            ),
            const SizedBox(height: 6),
            Text(
              '高中数学讲解会把高难题交给推理模型，读图、排课、复核交给快速模型。修改 local.config.json 后需重启服务。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: const Icon(Icons.network_check),
              label: Text(_testing ? '正在检测全部模型…' : '检测全部模型'),
            ),
            if (_connection.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(_connection),
                ),
              ),
          ],
          _field(_baseUrl, 'AI Base URL', 'https://your-host/v1'),
          _field(_apiKey, 'API Key', 'sk-...'),
          _field(_model, '快速/结构化模型', 'your-fast-model'),
          _field(_reasoningModel, '高难推理模型', 'your-reasoning-model'),
          _field(_visionModel, '多模态模型（图片识别）', 'your-vision-model'),
          const SizedBox(height: 16),

          _insightCard(),
          const SizedBox(height: 16),

          for (final b in _boards.values.where((b) => b.name != '互动讲解'))
            _boardCard(b),
          Card(
            child: ListTile(
              title: const Text('数学互动讲解'),
              subtitle: Text(
                '服务地址：${LessonAiConfig.externalLessonBridgeUrl}\n快速模型：${ApiEndpoints.model}\n推理模型：${ApiEndpoints.reasoningModel}\n视觉模型：${ApiEndpoints.visionModel}',
              ),
            ),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppPressScale(
                  pressedScale: 0.864,
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存设置'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AppPressScale(
                pressedScale: 0.864,
                child: OutlinedButton.icon(
                  onPressed: _resetAll,
                  icon: const Icon(Icons.restore),
                  label: const Text('恢复默认'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 学习画像卡片：自动统计展示 + 手动薄弱点编辑。
  Widget _insightCard() {
    final insight = ref.watch(studentInsightProvider);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, size: 20, color: Color(0xFF007AFF)),
                const SizedBox(width: 8),
                Text('学习画像', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (insight.updatedAt > 0)
                  Text(
                    '诊断更新 ${_fmtTime(insight.updatedAt)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6E6E73),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '由你的错题数据自动生成，AI 讲解会参考它实现个性化；也可手动补充薄弱点说明。',
              style: TextStyle(fontSize: 12, color: Color(0xFF6E6E73)),
            ),
            const SizedBox(height: 16),
            AnalyticsDashboard(
              data: WrongQuestionAnalytics(
                ref.watch(analyticsQuestionsProvider),
                now: DateTime.now(),
              ),
              profile: true,
              trace: insight.errorTrace,
              onShowQuestions: (title, questions) =>
                  showAnalyticsQuestions(context, title, questions),
            ),
            const SizedBox(height: 12),
            const Text(
              '手动补充薄弱点（可选）',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _weakPointsController,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                hintText: '例如：导数与单调性不熟练；圆锥曲线综合题容易漏掉分类讨论…',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: AppPressScale(
                pressedScale: 0.864,
                child: FilledButton(
                  onPressed: _saveWeakPoints,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  child: const Text('保存薄弱点'),
                ),
              ),
            ),
            // ── 具体错误点时间线（完整可追溯）──
            if (insight.errorTrace.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.history, size: 18, color: AppColors.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '具体错误点历史（${insight.errorTrace.length} 条，最多保留 200 条）',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '每次专家/快速讲解的错因与你的疑问点自动入档；AI 新题命中同类错误会主动提醒',
                style: TextStyle(fontSize: 12, color: Color(0xFF6E6E73)),
              ),
              const SizedBox(height: 8),
              ...insight.errorTrace.reversed.take(5).map((e) => _traceItem(e)),
              if (insight.errorTrace.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '… 共 ${insight.errorTrace.length} 条',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6E6E73),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _saveWeakPoints() {
    ref
        .read(studentInsightProvider.notifier)
        .setManualWeakPoints(_weakPointsController.text);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存学习画像')));
  }

  String _fmtTime(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// 单条具体错误点时间线条目。
  Widget _traceItem(Map<String, dynamic> e) {
    final ts = (e['ts'] as num?)?.toInt() ?? 0;
    final doubt = e['doubt']?.toString() ?? '';
    final keyPoint = e['key_point']?.toString() ?? '';
    final errType = e['error_type']?.toString() ?? '';
    final src = e['source'] == 'expert' ? '专家版' : '快速版';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.secondarySystem,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _fmtTime(ts),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6E6E73),
                  ),
                ),
                const SizedBox(width: 8),
                if (errType.isNotEmpty)
                  Text(
                    '错因：$errType',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.error,
                    ),
                  ),
                const Spacer(),
                Text(
                  src,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6E6E73),
                  ),
                ),
              ],
            ),
            if (keyPoint.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                keyPoint,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (doubt.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                '疑问点：$doubt',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  Widget _field(TextEditingController c, String label, String hint) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c,
      obscureText: label.contains('Key'),
      readOnly:
          ApiEndpoints.managedAi &&
          (label.contains('URL') ||
              label.contains('Key') ||
              c == _model ||
              c == _reasoningModel ||
              c == _visionModel),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
      ),
    ),
  );

  Widget _boardCard(_BoardForm b) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ExpansionTile(
      leading: const Icon(Icons.smart_toy_outlined, color: AppColors.primary),
      title: Text(b.name),
      subtitle: const Text(
        'URL / Key / 模型 / 提示词（留空 = 用全局默认）',
        style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(b.url, 'Base URL（覆盖全局）', '留空跟随全局'),
        _field(b.key, 'API Key（覆盖全局）', '留空跟随全局'),
        _field(b.model, '模型（覆盖全局）', '留空跟随全局'),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('系统提示词', style: Theme.of(context).textTheme.labelMedium),
        ),
        TextField(
          controller: b.prompt,
          maxLines: 10,
          minLines: 5,
          decoration: const InputDecoration(
            hintText: '留空使用内置默认提示词',
            alignLabelWithHint: true,
          ),
        ),
      ],
    ),
  );
}

/// 板块表单控制器集合。
class _BoardForm {
  final String name;
  final url = TextEditingController();
  final key = TextEditingController();
  final model = TextEditingController();
  final prompt = TextEditingController();
  _BoardForm(this.name);

  void load(BoardAiConfig c) {
    url.text = c.baseUrl;
    key.text = c.apiKey;
    model.text = c.model;
    prompt.text = c.prompt;
  }

  BoardAiConfig toConfig() => BoardAiConfig(
    baseUrl: url.text.trim(),
    apiKey: key.text.trim(),
    model: model.text.trim(),
    prompt: prompt.text.trim(),
  );

  void dispose() {
    url.dispose();
    key.dispose();
    model.dispose();
    prompt.dispose();
  }
}
