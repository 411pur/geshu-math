import 'package:geshu_math/features/lesson_studio/models/lesson_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

/// 每一处题目解析底部都会放「生成讲解视频」入口，它的可用条件由 [LessonGenerationInput] 决定。
/// （入口组件本身 import 了讲解播放器，那条链路依赖 web-only 的 dart:js_interop，
/// 在 VM 测试平台无法编译，所以这里直接钉住判定逻辑本身。）
void main() {
  test('只有题目图片时可以生成', () {
    const input = LessonGenerationInput(imageDataUrl: 'data:image/png;base64,aGVsbG8=');
    expect(input.hasMaterial, isTrue);
    expect(input.hasImage, isTrue);
  });

  test('只有题干文字时可以生成（不再要求必须拍照）', () {
    const input = LessonGenerationInput(questionText: '一物块在水平地面上受 8 N 拉力仍静止，求摩擦力。');
    expect(input.hasMaterial, isTrue);
    expect(input.hasImage, isFalse);
  });

  test('只有选项也算有素材', () {
    const input = LessonGenerationInput(options: ['A. 10 N', 'B. 8 N']);
    expect(input.hasMaterial, isTrue);
  });

  test('文字与图片都没有时不可生成，并且空串/空白不算素材', () {
    expect(const LessonGenerationInput().hasMaterial, isFalse);
    expect(const LessonGenerationInput(imageDataUrl: '   ', questionText: '\n').hasMaterial, isFalse);
  });

  test('图片与题干可以同时给（手写题既发图也发题干）', () {
    const input = LessonGenerationInput(
      imageDataUrl: 'data:image/png;base64,aGVsbG8=',
      questionText: '如图，物块静止在水平面上。',
      options: ['A. 8 N'],
      refId: 12,
      refKind: 'wrongQuestion',
    );
    expect(input.hasMaterial, isTrue);
    expect(input.refId, 12);
    expect(input.refKind, 'wrongQuestion');
  });
}
