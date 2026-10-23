/// 运行时可用的 AI 服务配置。
///
/// 默认值为空：真实值由 main() 在 runApp 之前从 `/config.json` 注入。
/// 只要目标服务兼容 OpenAI 的 `chat/completions` 协议，改 `baseUrl` /
/// `apiKey` / `model` 就能切换服务商与模型，无需改代码。
class ApiEndpoints {
  ApiEndpoints._();

  /// OpenAI 兼容接口 base URL（例如 `https://your-host/v1`）。
  static String baseUrl = '';

  /// API Key（浏览器端直连会暴露 key，仅供本地 / 演示；公网请用 AI 网关）。
  static String apiKey = '';

  /// 默认文本模型。
  static String model = '';

  /// 多模态模型（图片识别用）。
  static String visionModel = '';

  /// 推理模型（可选，留空则不启用）。
  static String reasoningModel = '';

  /// 是否把系统提示词托管到服务端（AI 网关）。
  ///
  /// 为 true 时：未自定义 prompt 的板块不再把内置系统提示词发给模型，改由网关
  /// 按 `X-Board` 头注入——提示词因此不再出现在前端 bundle 里。需先部署
  /// `ai_proxy/` 并把 [baseUrl] 指向网关。默认 false。
  static bool useServerPrompts = false;

  /// 占位符 / 空值识别。
  ///
  /// 未配置时不能把 `YOUR_API_KEY` 之类的占位串当成真 Key 发出去：那样拿到的是
  /// 服务端 401，而不是「没配 Key」这种一眼能看懂的提示。
  static bool isPlaceholder(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v.isEmpty) return true;
    return v.startsWith('your_') ||
        v.startsWith('your-') ||
        v == 'sk-' ||
        v == 'sk-xxx' ||
        v == 'sk-xxxx';
  }
}
