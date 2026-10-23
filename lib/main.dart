import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/constants/api_endpoints.dart';
import 'data/database/data_store.dart';
import 'data/database/db_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadConfig();

  // DataStore 必须在 runApp 之前初始化完成，并以同步 Provider 注入。
  //
  // 错题指导 / 知识图谱 / 考试分析的数据源都是同步 Provider，拿不到 store 会抛
  // "DataStore not initialized"；而 Provider 一旦进入 error 状态，之后每次读取
  // 都会变成 "Tried to use a provider that is in error state"。之前的症状就是
  // 错题讲解已经流式生成完了，保存错题那一步整页报这个错。
  final store = DataStore();
  try {
    await store.initialize();
  } catch (error, stackTrace) {
    // 初始化失败也要把应用启起来：让错误在具体页面里可见、可重试，
    // 而不是整页白屏。
    debugPrint('[boot] DataStore 初始化失败：$error');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(
    ProviderScope(
      overrides: [dataStoreProvider.overrideWithValue(store)],
      child: const GeShuZhiLiApp(),
    ),
  );
}

Future<void> _loadConfig() async {
  final data = await loadConfigMap();
  if (data == null) {
    debugPrint('[config] 未读到 config.json，使用 ApiEndpoints 默认值');
    return;
  }
  _applyConfig(data);
  debugPrint(
    '[config] 已加载 config.json：'
    'baseUrl=${ApiEndpoints.baseUrl} '
    'model=${ApiEndpoints.model} '
    'vision=${ApiEndpoints.visionModel} '
    'serverPrompts=${ApiEndpoints.useServerPrompts} '
    'keyReady=${!ApiEndpoints.isPlaceholder(ApiEndpoints.apiKey)}',
  );
}

void _applyConfig(Map<String, dynamic> data) {
  // config.json 支持把 AI 配置收口在 ai 段，也支持顶层扁平字段。
  // 两种形态都要认 —— 只读一种会让 Key 读不到，回落到占位符，
  // 结果是错题指导 / 考试分析 / 智能问答 / 报告 / 图片识别全部 401。
  final aiRaw = data['ai'];

  String pick(List<String> keys) {
    for (final key in keys) {
      for (final source in [data, if (aiRaw is Map) aiRaw]) {
        final value = source[key];
        if (value is String &&
            value.trim().isNotEmpty &&
            !ApiEndpoints.isPlaceholder(value)) {
          return value.trim();
        }
      }
    }
    return '';
  }

  final baseUrl = pick(['apiBaseUrl', 'baseUrl']);
  if (baseUrl.isNotEmpty) ApiEndpoints.baseUrl = baseUrl;

  final apiKey = pick(['apiKey']);
  if (apiKey.isNotEmpty) ApiEndpoints.apiKey = apiKey;

  final model = pick(['model']);
  if (model.isNotEmpty) ApiEndpoints.model = model;

  final visionModel = pick(['visionModel']);
  if (visionModel.isNotEmpty) ApiEndpoints.visionModel = visionModel;

  final reasoningModel = pick(['reasoningModel']);
  if (reasoningModel.isNotEmpty) ApiEndpoints.reasoningModel = reasoningModel;

  // 提示词/Key 是否托管到 AI 网关（ai_proxy/）。默认 false（前端内置提示词）；
  // 部署网关后把 config.json 的 useServerPrompts 置 true 即可切换。
  final useServerPrompts =
      (aiRaw is Map ? aiRaw['useServerPrompts'] : null) ??
      data['useServerPrompts'];
  if (useServerPrompts is bool) {
    ApiEndpoints.useServerPrompts = useServerPrompts;
  }
}
