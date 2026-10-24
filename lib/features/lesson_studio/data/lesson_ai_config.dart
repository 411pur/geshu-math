import '../../home/providers/ai_settings_models.dart';

/// 互动讲解（生成讲解视频/HTML）的原讲解服务桥接配置。
///
/// 配置来源（优先序）：
/// 1. 浏览器设置页的「互动讲解」板块（[AiSettings.lesson]，经 [applyBoard] 同步）
/// 2. web/config.json 的 lessonStudio 段（[main] 启动时经 [apply] 注入的默认值）
class LessonAiConfig {
  // 原讲解生成服务地址（Node 引擎）。默认指向本机引擎，web/config.json 或设置页可覆盖。
  static String externalLessonBridgeUrl = 'http://127.0.0.1:3210';
  static int timeoutMs = 180000;
  static String model = ''; // 讲解生成所用模型（展示/配置用，留空跟随全局或引擎侧默认）

  // 文件版本（web/config.json 或 local.config.json）的默认值。
  // 浏览器设置页把「互动讲解」板块清空时会回退到这里，而不是停留在旧的浏览器覆盖值上。
  static String _fileBridgeUrl = externalLessonBridgeUrl;
  static String _fileModel = '';

  /// 桥接地址是否可用：必须是 http(s) 且不是占位符。
  ///
  /// 少了这道校验，config.json 里留空的 externalLessonBridgeUrl 会把地址清成
  /// 空串，「互动讲解」就直接报「未配置服务地址」——看起来像功能坏了，
  /// 其实只是默认值被空配置覆盖掉了。
  static bool _isUsableUrl(String value) {
    final v = value.trim();
    if (v.isEmpty || v.toLowerCase().startsWith('your_')) return false;
    return v.startsWith('http://') || v.startsWith('https://');
  }

  /// 去掉结尾多余的斜杠，避免拼出 //api/projects 这种地址。
  static String _normalizeUrl(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

  /// 应用 web/config.json 里的 lessonStudio 段落（启动默认值）。
  static void apply(Object? raw) {
    if (raw is! Map) return;
    final m = raw.map((key, value) => MapEntry(key.toString(), value));

    final bridgeUrl = m['externalLessonBridgeUrl'];
    if (bridgeUrl is String && _isUsableUrl(bridgeUrl)) {
      externalLessonBridgeUrl = _normalizeUrl(bridgeUrl);
      _fileBridgeUrl = externalLessonBridgeUrl;
    }
    if (m['timeoutMs'] is num) {
      timeoutMs = (m['timeoutMs'] as num).toInt().clamp(30000, 600000);
    }
    if (m['model'] is String) {
      model = (m['model'] as String).trim();
      _fileModel = model;
    }
  }

  /// 把浏览器设置页的「互动讲解」板块配置同步到本桥接层。
  /// 板块里留空的字段视为「恢复默认」：回退到文件版本（web/config.json 等）的默认值，
  /// 而不是保留上一次浏览器覆盖值。只有用户显式填写的字段才覆盖文件默认。
  static void applyBoard(BoardAiConfig board) {
    if (_isUsableUrl(board.baseUrl)) {
      externalLessonBridgeUrl = _normalizeUrl(board.baseUrl);
    } else {
      externalLessonBridgeUrl = _fileBridgeUrl;
    }
    if (board.model.trim().isNotEmpty) {
      model = board.model.trim();
    } else {
      model = _fileModel;
    }
    if (board.apiKey.trim().isNotEmpty) {
      // 原讲解服务如果要求鉴权 Key，可在此预留（当前 Node 引擎由服务端 .env 管 Key）
    }
  }
}
