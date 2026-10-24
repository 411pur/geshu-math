/// 生成一次互动讲解所需的素材。
///
/// 图片与题干至少要有一个：
/// - 手写题、带图题必须给 [imageDataUrl]（引擎用视觉模型读图 + 重画原图）；
/// - 纯文字题（学生手打、或抽掉了图片的错题）只给 [questionText] 也能生成——
///   引擎侧 `POST /api/projects` 本来就接受纯文字，这里不再人为要求必须拍照。
class LessonGenerationInput {
  final String imageDataUrl;
  final String questionText;
  final List<String> options;
  final int refId;
  final String refKind;

  const LessonGenerationInput({
    this.imageDataUrl = '',
    this.questionText = '',
    this.options = const [],
    this.refId = 0,
    this.refKind = '',
  });

  bool get hasImage => imageDataUrl.trim().isNotEmpty;

  bool get hasText => questionText.trim().isNotEmpty || options.isNotEmpty;

  /// 是否具备生成素材：调用方据此决定按钮可用态，避免"点了只弹一句提示"。
  bool get hasMaterial => hasImage || hasText;
}
