import 'dart:typed_data';

/// 文档扫描抽象：选图并返回图片字节。
///
/// Web/桌面端仅支持从相册/文件选择（无摄像头）；移动端可用相机。
/// 离线自动切边（扫描全能王式）需要移动端原生插件，在 Web 目标下不可用，
/// 故此处只负责"取图"，识别与理解交给多模态视觉 LLM。
abstract class DocumentScannerService {
  /// 选图并返回图片字节；用户取消返回 null。
  Future<Uint8List?> captureAndCrop();
}
