/// 兜底实现：既非 IO 也非 Web 的平台（理论上不存在）返回 null。
///
/// 保留它是为了让 [app_config.dart] 的条件导出永远解析得到实现。
Future<Map<String, dynamic>?> loadConfigMap() async => null;
