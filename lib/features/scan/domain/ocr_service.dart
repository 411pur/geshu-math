import 'dart:typed_data';

/// 一次识别的产物：题目文字 + 解析出的选项。
class OcrOutcome {
  final String text;
  final List<String> options;

  const OcrOutcome({required this.text, this.options = const []});
}

/// 识别异常（如未配置多模态模型 Key）。
class OcrException implements Exception {
  final String message;
  const OcrException(this.message);
  @override
  String toString() => message;
}

/// 文字识别抽象：对给定图片字节做 OCR，返回题目文字与选项。
abstract class OcrService {
  /// 识别图片中的题目，返回文字与（若有）选项。
  Future<OcrOutcome> recognize(Uint8List imageBytes);

  /// 释放底层资源。
  void dispose();
}
