import 'dart:convert';

import 'package:dio/dio.dart';

/// Web 端：config.json 是站点根目录下的静态资源（本工程即 web/config.json，
/// 构建时会被拷进 build/web）。
///
/// 关键修正：URL 上带一个时间戳参数 —— 否则浏览器/Service Worker 会把
/// "改过但同名"的 config.json 缓存住，表现为刷新页面后配置依旧是旧的。
Future<Map<String, dynamic>?> loadConfigMap() async {
  try {
    final resp = await Dio().get<String>(
      '/config.json?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    if (resp.statusCode != 200) return null;
    final body = resp.data;
    if (body == null || body.isEmpty) return null;
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
