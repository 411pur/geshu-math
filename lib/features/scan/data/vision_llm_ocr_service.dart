import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../data/ocr_response_parser.dart';
import '../domain/ocr_service.dart';

/// 基于项目自带「多模态视觉 LLM」的题目识别（Web/桌面/移动全平台可用）。
///
/// 相比离线 ML Kit：
/// - 不依赖任何移动端原生插件，在 Web 目标下也能跑；
/// - 直接读取图片中的**公式 / 希腊字母 / 手绘图像**（ML Kit 对这类很弱）；
/// - 复用 web/config.json 里已配置的多模态模型（ApiEndpoints.aliyunVisionModel）。
class VisionLlmOcrService implements OcrService {
  final Dio dio;

  const VisionLlmOcrService(this.dio);

  @override
  Future<OcrOutcome> recognize(Uint8List imageBytes) async {
    final baseUrl = ApiEndpoints.aliyunBaseUrl;
    final apiKey = ApiEndpoints.aliyunApiKey;
    final visionModel = ApiEndpoints.aliyunVisionModel;

    if (apiKey.isEmpty || apiKey.startsWith('YOUR_')) {
      throw const OcrException(
        '尚未配置多模态模型：请先在「我的 → 设置」里填写视觉模型与 API Key，'
        '或由管理员在 web/config.json 的 ai 段配置后再使用。',
      );
    }

    final dataUri =
        'data:image/jpeg;base64,${base64Encode(imageBytes)}';
    final messages = [
      {
        'role': 'system',
        'content': _systemPrompt,
      },
      {
        'role': 'user',
        'content': [
          {
            'type': 'image_url',
            'image_url': {'url': dataUri},
          },
          {'type': 'text', 'text': '请识别以上初高中数学题，公式用 LaTeX 保留。'},
        ],
      },
    ];

    final resp = await dio.post(
      '$baseUrl/chat/completions',
      data: {
        'model': visionModel,
        'messages': messages,
        'temperature': 0.2,
        'response_format': {'type': 'json_object'},
      },
      options: Options(
        headers: {'Authorization': 'Bearer $apiKey'},
        responseType: ResponseType.json,
      ),
    );

    final content = _extractContent(resp.data);
    final (text, options) = parseVisionOcrResponse(content);
    return OcrOutcome(text: text, options: options);
  }

  String _extractContent(dynamic data) {
    try {
      final choices = data is Map ? data['choices'] as List? : null;
      final msg = choices?.isNotEmpty == true ? choices!.first['message'] : null;
      return (msg is Map ? msg['content'] as String? : null) ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {}

  static const String _systemPrompt = '''
你是数学题目识别助手。请仔细读取图片中的初高中数学题，原样转录题干与已知条件（含数值、小问），公式保留上下标、根号与分式（可用 LaTeX），并逐条列出选择题选项。
输出严格 JSON：{"question_text":"...","options":["A内容","B内容","C内容","D内容"]}。
非选择题 options 为空数组。只输出 JSON，不要任何多余文字或代码块。''';
}
