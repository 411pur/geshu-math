/// 运行时配置（config.json）的**平台无关出口**。
///
/// 设计要点：
///  * Web 端：config.json 是随站点一起发布的静态资源，走 HTTP 读取；
///    请求带上时间戳参数，避免浏览器缓存导致"改了配置刷新页面还是旧的"。
///  * 桌面端（Windows / macOS / Linux）：没有服务器根目录，原来那种
///    `dio.get('/config.json')` 必然失败 → 配置永远读不到 → 走默认占位 Key
///    → AI 调用被判为"无 Key"，视频退化成离线兜底的老样式。这里改成直接读文件，
///    并向上逐级找项目根，保证从任意子目录启动都能命中 web/config.json。
///
/// 未命中时返回 null，由调用方静默使用 ApiEndpoints 的默认值。
library;

export 'app_config_stub.dart'
    if (dart.library.io) 'app_config_io.dart'
    if (dart.library.html) 'app_config_web.dart';
