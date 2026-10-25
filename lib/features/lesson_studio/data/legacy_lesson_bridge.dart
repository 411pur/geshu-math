import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/lesson_contracts.dart';
import '../models/lesson_project.dart';
import 'lesson_ai_config.dart';

class LessonBridgeException implements Exception {
  final String message;

  /// 网络断开、超时这类错误可以短暂重试；模型拒绝、输入错误等业务错误不能重试。
  final bool retryable;
  const LessonBridgeException(this.message, {this.retryable = false});
  @override
  String toString() => message;
}

class LegacyLessonStatus {
  final String externalId, title, subject, message, error;
  final LessonProjectStage stage;
  final LessonProjectStatus status;
  final double progress;
  final List<String> visualWarnings;

  const LegacyLessonStatus({
    required this.externalId,
    required this.title,
    required this.subject,
    required this.message,
    required this.error,
    required this.stage,
    required this.status,
    required this.progress,
    required this.visualWarnings,
  });

  bool get isDone => status == LessonProjectStatus.done;
  bool get isFailed => status == LessonProjectStatus.failed;
}

class LegacyLessonResult {
  final String externalId, title, subject, html;
  final List<String> visualWarnings;

  const LegacyLessonResult({
    required this.externalId,
    required this.title,
    required this.subject,
    required this.html,
    required this.visualWarnings,
  });
}

class LegacyLessonBridge {
  static const Duration pollInterval = Duration(seconds: 1);
  // 40 分钟。引擎各阶段超时相加最坏能到 40 分钟量级（读图 120s + 求解 180s×2 +
  // 原图重建 90s/180s + 排课 240s×3 + 复核 90s×3 + 视觉检查与修复约 10 分钟），
  // 难题（电磁感应双杆）实测一轮 7-10 分钟。上限设低了，学生就会看到"任务超时"
  // 而其实引擎还在正常跑——轮询期间进度条一直有阶段更新，等待是有反馈的。
  static const int maxPollAttempts = 2400;
  static const int maxTransientFailures = 15;

  final Dio? dio;

  const LegacyLessonBridge({this.dio});

  Dio _client() =>
      dio ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: Duration(milliseconds: LessonAiConfig.timeoutMs),
        ),
      );

  String get _baseUrl => LessonAiConfig.externalLessonBridgeUrl
      .trim()
      .replaceFirst(RegExp(r'/$'), '');

  Future<String> create(LessonGenerationInput input) async {
    final baseUrl = _baseUrl;
    if (baseUrl.isEmpty) {
      throw const LessonBridgeException(
        '未配置互动讲解服务地址：请双击「启动项目.bat」重新生成前端配置；手动配置时请填写当前统一服务地址（默认 http://127.0.0.1:8124）。',
      );
    }
    final image = input.hasImage ? _decodeDataUrl(input.imageDataUrl) : null;
    final text = _composeQuestionText(input);
    if (image == null && text.isEmpty) {
      throw const LessonBridgeException('缺少题目素材：请提供题目图片或题目文字');
    }
    final form = FormData();
    if (image != null) {
      form.files.add(
        MapEntry(
          'image',
          MultipartFile.fromBytes(
            image.bytes,
            filename: image.fileName,
            contentType: DioMediaType.parse(image.mimeType),
          ),
        ),
      );
    }
    // 引擎侧 /api/projects 同时接受 image 与 text（parseProjectInput）；
    // 纯文字题必须把题干发过去，否则写稿模型只能从"学生那句提问"里反推题目。
    if (text.isNotEmpty) form.fields.add(MapEntry('text', text));
    try {
      final response = await _client().post<Map<String, dynamic>>(
        '$baseUrl/api/projects',
        data: form,
      );
      final id = response.data?['id']?.toString() ?? '';
      if (id.isEmpty) {
        throw const LessonBridgeException('数学讲解服务未返回任务 ID');
      }
      return id;
    } on DioException catch (error) {
      throw LessonBridgeException('数学讲解服务连接失败：${describeDioError(error)}');
    }
  }

  /// 题干 + 选项拼成引擎可读的题目文字（选项按行列出，选择题才不会丢选项）。
  String _composeQuestionText(LessonGenerationInput input) {
    final buffer = StringBuffer(input.questionText.trim());
    final options = input.options
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .toList();
    if (options.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write('选项：\n${options.join('\n')}');
    }
    return buffer.toString().trim();
  }

  /// 把文档（PDF / Word / 纯文本）交给引擎取文。
  ///
  /// PDF 与 DOCX 的解析放在引擎侧：Node 有 pdf.js（Apache-2.0）与 mammoth（BSD-2），
  /// Flutter Web 侧没有等价且许可干净的实现。失败时优先把引擎给的人话提示透出去。
  Future<String> extractDocument({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final baseUrl = _baseUrl;
    if (baseUrl.isEmpty) {
      throw const LessonBridgeException(
        '未配置互动讲解服务地址：请双击「启动项目.bat」重新生成前端配置；手动配置时请填写当前统一服务地址（默认 http://127.0.0.1:8124）。',
      );
    }
    final form = FormData();
    form.files.add(
      MapEntry('file', MultipartFile.fromBytes(bytes, filename: fileName)),
    );
    try {
      final response = await _client().post<Map<String, dynamic>>(
        '$baseUrl/api/extract-text',
        data: form,
      );
      final text = response.data?['text']?.toString() ?? '';
      if (text.trim().isEmpty) {
        throw const LessonBridgeException('没有从文件里读到文字：扫描件或纯图片 PDF 请改用「上传图片」');
      }
      return text;
    } on DioException catch (error) {
      final payload = error.response?.data;
      final engineMessage = payload is Map
          ? payload['message']?.toString()
          : null;
      throw LessonBridgeException(
        '文档解析失败：${engineMessage?.isNotEmpty == true ? engineMessage : describeDioError(error)}',
      );
    }
  }

  Future<LegacyLessonStatus> status(String externalId) async {
    final baseUrl = _baseUrl;
    if (baseUrl.isEmpty) {
      throw const LessonBridgeException(
        '未配置互动讲解服务地址：请双击「启动项目.bat」重新生成前端配置；手动配置时请填写当前统一服务地址（默认 http://127.0.0.1:8124）。',
      );
    }
    try {
      final response = await _client().get<Map<String, dynamic>>(
        '$baseUrl/api/projects/$externalId',
      );
      final raw = response.data?['project'];
      if (raw is! Map) {
        throw const LessonBridgeException('数学讲解服务返回的任务状态无效');
      }
      final project = raw.map((key, value) => MapEntry(key.toString(), value));
      return LegacyLessonStatus(
        externalId: externalId,
        title: project['title']?.toString().trim() ?? '',
        subject: project['subject']?.toString().trim() ?? '',
        message: project['message']?.toString().trim() ?? '',
        error: project['error']?.toString().trim() ?? '',
        stage: _stage(project['stage']?.toString() ?? ''),
        status: LessonProjectStatusJson.parse(project['status']),
        progress: ((project['progress'] as num?)?.toDouble() ?? 0).clamp(
          0,
          100,
        ),
        visualWarnings: _strings(project['visualWarnings']),
      );
    } on DioException catch (error) {
      throw LessonBridgeException(
        '查询数学讲解任务失败：${describeDioError(error)}',
        retryable: _isTransientDio(error),
      );
    }
  }

  Future<String> html(String externalId) async {
    final baseUrl = _baseUrl;
    if (baseUrl.isEmpty) {
      throw const LessonBridgeException('未配置数学讲解生成服务地址');
    }
    try {
      final response = await _client().get<String>(
        '$baseUrl/api/projects/$externalId/html',
        options: Options(responseType: ResponseType.plain),
      );
      final html = response.data?.trim() ?? '';
      if (html.isEmpty) {
        throw const LessonBridgeException('数学讲解服务未返回 HTML');
      }
      return html;
    } on DioException catch (error) {
      throw LessonBridgeException(
        '读取数学讲解 HTML 失败：${describeDioError(error)}',
        retryable: _isTransientDio(error),
      );
    }
  }

  Future<LegacyLessonResult> wait(
    String externalId, {
    required Future<void> Function(LessonProgressEvent event) onProgress,
  }) async {
    LegacyLessonStatus? status;
    var transientFailures = 0;
    for (var attempt = 0; attempt < maxPollAttempts; attempt++) {
      try {
        status = await this.status(externalId);
        transientFailures = 0;
      } on LessonBridgeException catch (error) {
        if (!error.retryable || ++transientFailures > maxTransientFailures) {
          rethrow;
        }
        await onProgress(
          LessonProgressEvent(
            stage: status?.stage ?? LessonProjectStage.extracting,
            progress: (status?.progress ?? 5).clamp(0, 99),
            message:
                '数学讲解服务暂时断开，正在重连（$transientFailures/$maxTransientFailures）',
          ),
        );
        await Future<void>.delayed(pollInterval);
        continue;
      }
      await onProgress(_progressEvent(status));
      if (status.isDone) break;
      if (status.isFailed) {
        throw LessonBridgeException(
          '数学讲解任务失败：${status.error.isEmpty ? '未知错误' : status.error}',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
    if (status == null || !status.isDone) {
      throw const LessonBridgeException('数学讲解任务超时，请重新生成');
    }

    String lessonHtml = '';
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        lessonHtml = await html(externalId);
        break;
      } on LessonBridgeException catch (error) {
        lastError = error;
        if (!error.retryable || attempt == 2) rethrow;
        await Future<void>.delayed(pollInterval);
      }
    }
    if (lessonHtml.isEmpty) {
      throw LessonBridgeException('读取数学讲解 HTML 失败：${lastError ?? '服务未返回内容'}');
    }
    return LegacyLessonResult(
      externalId: externalId,
      title: status.title.isEmpty ? '互动讲解' : status.title,
      subject: status.subject,
      html: lessonHtml,
      visualWarnings: status.visualWarnings,
    );
  }

  static LessonProgressEvent _progressEvent(LegacyLessonStatus status) =>
      LessonProgressEvent(
        stage: status.stage,
        progress: status.progress.clamp(0, 99),
        message: status.message.isEmpty
            ? _messageForStage(status.stage)
            : status.message,
      );

  static LessonProjectStage _stage(String value) {
    return switch (value) {
      'extracting' => LessonProjectStage.extracting,
      'solving' => LessonProjectStage.solving,
      'verifying' => LessonProjectStage.verifying,
      'planning' => LessonProjectStage.planning,
      'rendering' => LessonProjectStage.rendering,
      'visual_check' => LessonProjectStage.visualCheck,
      'repairing' => LessonProjectStage.repairing,
      'done' => LessonProjectStage.done,
      'failed' => LessonProjectStage.failed,
      _ => LessonProjectStage.queued,
    };
  }

  static String _messageForStage(LessonProjectStage stage) => switch (stage) {
    LessonProjectStage.extracting => '正在读取题目和图形信息',
    LessonProjectStage.solving => '正在独立求解并核对原答案',
    LessonProjectStage.verifying => '正在自动检查公式、单位和答案',
    LessonProjectStage.planning => '正在编排老师讲解步骤',
    LessonProjectStage.rendering => '正在生成互动黑板 HTML',
    LessonProjectStage.visualCheck => '正在检查板书布局',
    LessonProjectStage.repairing => '正在自动修复视觉问题',
    LessonProjectStage.done => '讲解 HTML 已生成',
    LessonProjectStage.failed => '生成失败',
    LessonProjectStage.queued => '等待开始',
  };

  static bool _isTransientDio(DioException error) => switch (error.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => true,
    DioExceptionType.unknown => error.response == null,
    _ => false,
  };

  static String describeDioError(DioException error) {
    if (_isTransientDio(error)) {
      return '讲题引擎未运行或连接已断开。请双击项目根目录的「启动项目.bat」，'
          '等待终端出现“格数至理已启动”后重试；如果原任务已中断，请点击“重新生成”。'
          '排查日志位于 build/local-stack-logs/。';
    }
    final status = error.response?.statusCode;
    final payload = error.response?.data;
    if (payload is Map && payload['message'] != null) {
      return '服务返回 HTTP $status：${payload['message']}';
    }
    return status == null
        ? (error.message ?? error.toString())
        : '服务返回 HTTP $status，请检查模型配置或稍后重试';
  }

  static List<String> _strings(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((item) => item.toString()).take(30).toList();
  }

  static _DecodedImage? _decodeDataUrl(String value) {
    final comma = value.indexOf(',');
    if (comma <= 0) return null;
    final header = value.substring(0, comma);
    final mime = RegExp(r'data:([^;]+)').firstMatch(header)?.group(1);
    try {
      final bytes = base64Decode(value.substring(comma + 1));
      final normalizedMime = mime == null || mime.isEmpty ? 'image/png' : mime;
      final extension = switch (normalizedMime) {
        'image/jpeg' => 'jpg',
        'image/webp' => 'webp',
        _ => 'png',
      };
      return _DecodedImage(
        bytes: bytes,
        mimeType: normalizedMime,
        fileName: 'question.$extension',
      );
    } catch (_) {
      return null;
    }
  }
}

class _DecodedImage {
  final Uint8List bytes;
  final String mimeType, fileName;

  const _DecodedImage({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });
}
