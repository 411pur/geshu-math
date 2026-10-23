/// 运行时可用的 AI 服务配置。
///
/// 这里的默认值是**占位符**，真实值由 main() 在 runApp 之前从 web/config.json 注入。
/// 配置可写在 ai 段，也可写在顶层扁平字段（两种形态都支持）。
///
/// 注意：config.json 里只有 DeepSeek Key、没有阿里云 Key 时，usingDeepSeek
/// 会被置为 true，baseUrl / model / visionModel 全部指向 DeepSeek —— 这两家
/// 都是 OpenAI 兼容协议，请求体与流式解析完全一致，切换只需换地址与模型名。
class ApiEndpoints {
  ApiEndpoints._();

  /// OpenAI 兼容接口 base URL（DashScope 或 DeepSeek）。
  static String aliyunBaseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';

  /// API Key（注意：浏览器端直连会暴露 key，仅供本地 / 教学演示）。
  static String aliyunApiKey = 'YOUR_ALIYUN_API_KEY';

  /// 默认文本模型。
  static String aliyunModel = 'qwen-plus';

  /// 多模态模型（错题图片识别用）。
  static String aliyunVisionModel = 'qwen-vl-plus';

  /// 推理模型。
  static String aliyunReasoningModel = 'qwen-max';

  /// 当前实际生效的服务商是否为 DeepSeek。
  ///
  /// 为 true 时客户端会忽略设置页 / localStorage 里残留的 qwen-* 模型名与
  /// DashScope 地址 —— 拿 DeepSeek 的 Key 去打阿里云一定 401，拿 qwen-vl-plus
  /// 去打 DeepSeek 一定 400，这类"串味"配置比没配置更难排查。
  static bool usingDeepSeek = false;

  /// 是否把系统提示词托管到服务端（AI 网关）。
  ///
  /// 为 true 时：未自定义 prompt 的板块不再把内置系统提示词发给模型，改由网关
  /// 按 `X-Board` 头注入——提示词因此不再出现在前端 bundle 里。需先部署
  /// `ai_proxy/` 并把 [aliyunBaseUrl] 指向网关。默认 false（前端行为不变）。
  static bool useServerPrompts = false;

  /// 占位符 / 空值识别。
  ///
  /// 未配置时绝不能把 YOUR_ALIYUN_API_KEY 当成真 Key 发出去：那样拿到的是
  /// 服务端 401，而不是"没配 Key"这种一眼能看懂的提示。
  static bool isPlaceholder(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v.isEmpty) return true;
    return v.startsWith('your_') ||
        v.startsWith('your-') ||
        v.contains('your_aliyun') ||
        v == 'sk-' ||
        v == 'sk-xxx';
  }

  /// 模型名是否与当前服务商兼容（DeepSeek 模式拒绝 qwen-*）。
  static bool isModelCompatible(String model) {
    final v = model.trim();
    if (isPlaceholder(v)) return false;
    if (usingDeepSeek && v.toLowerCase().startsWith('qwen')) return false;
    return true;
  }
}
