import 'dart:typed_data';

/// 一次扫描识别的结果：原始图片字节 + 识别出的文字 + 解析出的选项。
class ScanResult {
  final Uint8List imageBytes;
  final String recognizedText;
  final List<String> options;

  const ScanResult({
    required this.imageBytes,
    required this.recognizedText,
    this.options = const [],
  });
}
