import 'package:geshu_math/features/lesson_studio/data/lesson_store.dart';
import 'package:geshu_math/features/lesson_studio/models/lesson_project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('内存讲解库支持保存、按错题反查、HTML 和删除', () async {
    final store = MemoryLessonStore();
    final now = DateTime(2026, 9, 25);
    await store.saveRecord(
      LessonProjectRecord(
        id: 'lesson-1',
        title: '电场题',
        refId: 7,
        refKind: 'wrongQuestion',
        createdAt: now,
        updatedAt: now,
        hasHtml: true,
      ),
    );
    await store.saveHtml('lesson-1', '<html>lesson</html>');
    await store.saveArtifacts('lesson-1', {'score': 100});
    expect((await store.latestForRef(7, 'wrongQuestion'))?.id, 'lesson-1');
    expect(await store.loadHtml('lesson-1'), contains('lesson'));
    expect((await store.loadArtifacts('lesson-1'))?['score'], 100);
    await store.delete('lesson-1');
    expect(await store.getRecord('lesson-1'), isNull);
  });
}
