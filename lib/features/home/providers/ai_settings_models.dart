import '../../../core/constants/api_endpoints.dart';

/// 单个板块的 AI 配置（纯模型，无 dart:html，可在 VM 单测）。
/// 为空字段表示「跟随全局默认」（baseUrl/model 用全局，prompt 用内置默认提示词）。
class BoardAiConfig {
  final String baseUrl; // 空 = 用全局 baseUrl
  final String apiKey; // 空 = 用全局 apiKey
  final String model; // 空 = 用全局 model
  final String prompt; // 空 = 用内置默认提示词

  const BoardAiConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.prompt = '',
  });

  factory BoardAiConfig.fromJson(Map<String, dynamic> j) => BoardAiConfig(
    baseUrl: (j['baseUrl'] as String?) ?? '',
    apiKey: (j['apiKey'] as String?) ?? '',
    model: (j['model'] as String?) ?? '',
    prompt: (j['prompt'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'prompt': prompt,
  };

  bool get isEmpty =>
      baseUrl.isEmpty && apiKey.isEmpty && model.isEmpty && prompt.isEmpty;
}

/// 全局 AI 设置（纯模型；可被各板块覆盖）。
class AiSettings {
  final String baseUrl; // 全局 URL
  final String apiKey; // 全局 API Key
  final String model; // 全局文本模型
  final String reasoningModel; // 高难推理模型
  final String visionModel; // 全局多模态模型
  final BoardAiConfig wrongQuestion; // 错题指导
  final BoardAiConfig exam; // 考试分析
  final BoardAiConfig qa; // 智能问答
  final BoardAiConfig report; // 学习报告
  final BoardAiConfig lesson; // 互动讲解/讲解视频生成（baseUrl=原讲解服务地址）

  const AiSettings({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.reasoningModel = '',
    this.visionModel = '',
    this.wrongQuestion = const BoardAiConfig(),
    this.exam = const BoardAiConfig(),
    this.qa = const BoardAiConfig(),
    this.report = const BoardAiConfig(),
    this.lesson = const BoardAiConfig(),
  });

  AiSettings resolve(AiSettings defaults, {bool managed = false}) {
    String pick(String v, String fallback) =>
        v.trim().isEmpty ? fallback : v.trim();
    BoardAiConfig board(BoardAiConfig b) =>
        managed ? BoardAiConfig(model: b.model, prompt: b.prompt) : b;
    return AiSettings(
      baseUrl: managed ? defaults.baseUrl : pick(baseUrl, defaults.baseUrl),
      apiKey: managed ? defaults.apiKey : pick(apiKey, defaults.apiKey),
      model: managed ? defaults.model : pick(model, defaults.model),
      reasoningModel: managed
          ? defaults.reasoningModel
          : pick(reasoningModel, defaults.reasoningModel),
      visionModel: managed
          ? defaults.visionModel
          : pick(visionModel, defaults.visionModel),
      wrongQuestion: board(wrongQuestion),
      exam: board(exam),
      qa: board(qa),
      report: board(report),
      lesson: managed ? const BoardAiConfig() : lesson,
    );
  }

  Map<String, dynamic> overrides(AiSettings defaults) {
    final result = toJson();
    final base = defaults.toJson();
    for (final key in [
      'baseUrl',
      'apiKey',
      'model',
      'reasoningModel',
      'visionModel',
    ]) {
      if (result[key] == base[key]) result[key] = '';
    }
    return result;
  }

  /// 默认值：来自 web/config.json（已加载进 ApiEndpoints）+ 内置提示词占位。
  factory AiSettings.defaults() => AiSettings(
    baseUrl: ApiEndpoints.baseUrl,
    apiKey: ApiEndpoints.apiKey,
    model: ApiEndpoints.model,
    reasoningModel: ApiEndpoints.reasoningModel,
    visionModel: ApiEndpoints.visionModel,
  );

  factory AiSettings.fromJson(Map<String, dynamic> j) => AiSettings(
    baseUrl: (j['baseUrl'] as String?) ?? '',
    apiKey: (j['apiKey'] as String?) ?? '',
    model: (j['model'] as String?) ?? '',
    reasoningModel: (j['reasoningModel'] as String?) ?? '',
    visionModel: (j['visionModel'] as String?) ?? '',
    wrongQuestion: j['wrongQuestion'] is Map
        ? BoardAiConfig.fromJson(j['wrongQuestion'] as Map<String, dynamic>)
        : const BoardAiConfig(),
    exam: j['exam'] is Map
        ? BoardAiConfig.fromJson(j['exam'] as Map<String, dynamic>)
        : const BoardAiConfig(),
    qa: j['qa'] is Map
        ? BoardAiConfig.fromJson(j['qa'] as Map<String, dynamic>)
        : const BoardAiConfig(),
    report: j['report'] is Map
        ? BoardAiConfig.fromJson(j['report'] as Map<String, dynamic>)
        : const BoardAiConfig(),
    lesson: j['lesson'] is Map
        ? BoardAiConfig.fromJson(j['lesson'] as Map<String, dynamic>)
        : const BoardAiConfig(),
  );

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'reasoningModel': reasoningModel,
    'visionModel': visionModel,
    'wrongQuestion': wrongQuestion.toJson(),
    'exam': exam.toJson(),
    'qa': qa.toJson(),
    'report': report.toJson(),
    'lesson': lesson.toJson(),
  };
}
