import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../domain/document_scanner_service.dart';

/// 基于 image_picker 的取图实现：从相册/文件选择，返回图片字节。
///
/// 统一用 gallery 以兼容 Web/桌面（Web 无摄像头）。移动端若要拍照，
/// 将 source 改为 [ImageSource.camera] 即可，其余逻辑不变。
class ImagePickerDocumentScanner implements DocumentScannerService {
  final ImagePicker picker;

  const ImagePickerDocumentScanner(this.picker);

  @override
  Future<Uint8List?> captureAndCrop() async {
    // 选图即压缩：限制最长边并降质量，显著减小送视觉 LLM 的 base64 体积，
    // 降低 token 成本与延迟，同时提升识别稳定性（过大原图反而易超时/截断）。
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 82,
    );
    if (picked == null) return null;
    return picked.readAsBytes();
  }
}
