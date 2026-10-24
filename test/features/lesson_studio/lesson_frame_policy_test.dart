import 'package:geshu_math/features/lesson_studio/data/lesson_frame_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 回归防线：讲解播放器把单文件 HTML 塞进 data: URL 的 iframe，子帧是 opaque origin，
  // 宿主不放行 fullscreen 就会被权限策略拦掉，黑板上的「全屏黑板」点了没反应。
  // 真正的行为验证在 lesson_engine/tests/browser.test.ts（真实 Edge + data: URL 子帧）。
  test('内嵌讲解 iframe 必须把 fullscreen 授权给子帧', () {
    expect(kLessonFrameAllow.trim().split(RegExp(r'\s+')), contains('fullscreen'));
  });
}
