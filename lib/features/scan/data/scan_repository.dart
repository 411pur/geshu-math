import '../domain/document_scanner_service.dart';
import '../domain/ocr_service.dart';
import '../domain/scan_result.dart';

/// 未获取到图片时抛出的异常。
class ScanException implements Exception {
  final String message;
  const ScanException(this.message);
  @override
  String toString() => message;
}

/// 编排"扫描 → 识别"的最小闭环（字节流，Web 友好）。
class ScanRepository {
  final DocumentScannerService scanner;
  final OcrService ocr;

  const ScanRepository({
    required this.scanner,
    required this.ocr,
  });

  /// 选图并识别题目；未选图或取图失败抛 [ScanException]。
  Future<ScanResult> scanAndRecognize() async {
    final bytes = await scanner.captureAndCrop();
    if (bytes == null || bytes.isEmpty) {
      throw const ScanException('未选择或未能获取图片');
    }
    final outcome = await ocr.recognize(bytes);
    return ScanResult(
      imageBytes: bytes,
      recognizedText: outcome.text.trim(),
      options: outcome.options,
    );
  }
}
