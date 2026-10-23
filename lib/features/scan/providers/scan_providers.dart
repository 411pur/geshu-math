import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../camera/camera_providers.dart';
import '../../../core/network/network_provider.dart';
import '../data/image_picker_document_scanner.dart';
import '../data/scan_repository.dart';
import '../data/vision_llm_ocr_service.dart';
import '../domain/document_scanner_service.dart';
import '../domain/ocr_service.dart';
import '../domain/scan_result.dart';

final documentScannerProvider = Provider<DocumentScannerService>(
  (ref) => ImagePickerDocumentScanner(ref.watch(imagePickerProvider)),
);

/// 多模态视觉 LLM 识别（Web/桌面/移动全平台可用）。
final ocrServiceProvider = Provider<OcrService>(
  (ref) => VisionLlmOcrService(ref.watch(dioProvider)),
);

final scanRepositoryProvider = Provider<ScanRepository>(
  (ref) => ScanRepository(
    scanner: ref.watch(documentScannerProvider),
    ocr: ref.watch(ocrServiceProvider),
  ),
);

/// 驱动扫描预览页的状态：保存最近一次识别结果。
final scanControllerProvider =
    AsyncNotifierProvider<ScanController, ScanResult?>(ScanController.new);

class ScanController extends AsyncNotifier<ScanResult?> {
  @override
  ScanResult? build() => null;

  Future<void> scan() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(scanRepositoryProvider).scanAndRecognize(),
    );
  }
}
