import '../../../core/constants/api_endpoints.dart';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ai_settings_models.dart';

export 'ai_settings_models.dart'; // BoardAiConfig / AiSettings（纯模型，无 dart:html）

/// 当前生效的 AI 配置（localStorage 覆盖 + config.json 默认合并）。
class AiSettingsNotifier extends Notifier<AiSettings> {
  static const _key = 'geshu_math_ai_settings';
  static const _version = 2;

  @override
  AiSettings build() {
    try {
      final raw = web.window.localStorage.getItem(_key);
      if (raw != null && raw.isNotEmpty) {
        final j = json.decode(raw) as Map<String, dynamic>;
        if (j['v'] == 1 || j['v'] == _version) {
          final saved=AiSettings.fromJson(j['s'] as Map<String,dynamic>);
          final resolved=saved.resolve(AiSettings.defaults(),managed:ApiEndpoints.managedAi);
          if(ApiEndpoints.managedAi) web.window.localStorage.removeItem(_key);
          return resolved;
        }
      }
    } catch (_) {}
    return AiSettings.defaults();
  }

  void save(AiSettings settings) {
    state = settings.resolve(AiSettings.defaults(),managed:ApiEndpoints.managedAi);
    try {
      web.window.localStorage.setItem(_key, json.encode({'v': _version, 's': state.overrides(AiSettings.defaults())}));
    } catch (_) {}
  }

  void saveBoard(String board, BoardAiConfig cfg) {
    final s = state;
    switch (board) {
      case 'wrongQuestion': save(AiSettings(baseUrl: s.baseUrl, apiKey: s.apiKey, model: s.model, visionModel: s.visionModel, wrongQuestion: cfg, exam: s.exam, qa: s.qa, report: s.report, lesson: s.lesson));
      case 'exam': save(AiSettings(baseUrl: s.baseUrl, apiKey: s.apiKey, model: s.model, visionModel: s.visionModel, wrongQuestion: s.wrongQuestion, exam: cfg, qa: s.qa, report: s.report, lesson: s.lesson));
      case 'qa': save(AiSettings(baseUrl: s.baseUrl, apiKey: s.apiKey, model: s.model, visionModel: s.visionModel, wrongQuestion: s.wrongQuestion, exam: s.exam, qa: cfg, report: s.report, lesson: s.lesson));
      case 'report': save(AiSettings(baseUrl: s.baseUrl, apiKey: s.apiKey, model: s.model, visionModel: s.visionModel, wrongQuestion: s.wrongQuestion, exam: s.exam, qa: s.qa, report: cfg, lesson: s.lesson));
      case 'lesson': save(AiSettings(baseUrl: s.baseUrl, apiKey: s.apiKey, model: s.model, visionModel: s.visionModel, wrongQuestion: s.wrongQuestion, exam: s.exam, qa: s.qa, report: s.report, lesson: cfg));
      default: save(s);
    }
  }

  void saveGlobal({String? baseUrl, String? apiKey, String? model, String? visionModel}) {
    final s = state;
    save(AiSettings(
      baseUrl: baseUrl ?? s.baseUrl,
      apiKey: apiKey ?? s.apiKey,
      model: model ?? s.model,
      visionModel: visionModel ?? s.visionModel,
      wrongQuestion: s.wrongQuestion, exam: s.exam, qa: s.qa, report: s.report, lesson: s.lesson,
    ));
  }

  /// 恢复默认：清除本地覆盖，回到 config.json 的出厂值。
  void reset() {
    try { web.window.localStorage.removeItem(_key); } catch (_) {}
    state = AiSettings.defaults();
  }
}

final aiSettingsProvider = NotifierProvider<AiSettingsNotifier, AiSettings>(
  AiSettingsNotifier.new,
);