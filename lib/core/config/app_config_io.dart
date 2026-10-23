import 'dart:convert';
import 'dart:io';

/// 桌面端：直接从文件系统读 web/config.json。
///
/// 为什么必须单独做一份：桌面端没有"站点根目录"，相对路径的 HTTP 请求
/// （`/config.json`）无法解析，会静默失败 —— 于是 ApiEndpoints 里始终是用
/// 默认占位 Key；缺少有效配置时相关 AI 功能会明确失败。
///
/// 查找顺序（命中即返回）：
///   1. 当前工作目录下的 web/config.json、config.json
///   2. 从当前目录逐级向上（最多 6 层）找同名文件
///       —— 覆盖"IDE / 快捷方式启动时工作目录不是项目根"的常见情况。
Future<Map<String, dynamic>?> loadConfigMap() async {
  const candidates = ['web/config.json', 'config.json'];

  Future<String?> readIfExists(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    try {
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  var dir = Directory.current;
  for (var level = 0; level < 6; level++) {
    for (final rel in candidates) {
      final body = await readIfExists(
          '${dir.path}${Platform.pathSeparator}$rel');
      if (body == null) continue;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // 文件内容不是合法 JSON：交给调用方用默认值
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
