import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/providers/ai_settings_provider.dart';
import 'aliyun_api_client.dart';

/// Shared Dio instance for all HTTP calls.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 10),
    contentType: 'application/json',
  ));
  return dio;
});

/// Single Aliyun DashScope client wired with the shared Dio instance.
/// 监听 aiSettingsProvider，设置变更后客户端自动重建，使用新配置。
final aliyunApiClientProvider = Provider<AliyunApiClient>((ref) {
  final dio = ref.watch(dioProvider);
  final settings = ref.watch(aiSettingsProvider);
  return AliyunApiClient(dio: dio, settings: settings);
});
