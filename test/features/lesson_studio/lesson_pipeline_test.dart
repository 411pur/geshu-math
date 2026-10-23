import 'package:geshu_math/features/lesson_studio/data/legacy_lesson_bridge.dart';
import 'package:geshu_math/features/lesson_studio/data/lesson_pipeline.dart';
import 'package:geshu_math/features/lesson_studio/data/lesson_store.dart';
import 'package:geshu_math/features/lesson_studio/models/lesson_contracts.dart';
import 'package:geshu_math/features/lesson_studio/models/lesson_project.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBridge extends LegacyLessonBridge {
  var statusCalls = 0;
  var done = true;
  var failed = false;

  _FakeBridge();

  @override
  Future<String> create(LessonGenerationInput input) async => 'remote-task-1';

  @override
  Future<LegacyLessonStatus> status(String externalId) async {
    statusCalls++;
    return LegacyLessonStatus(
      externalId: externalId,
      title: '原项目讲解',
      subject: '物理',
      message: failed
          ? '生成失败'
          : done
          ? '讲解 HTML 已生成'
          : '正在求解',
      error: failed ? '模型拒绝生成' : '',
      stage: failed
          ? LessonProjectStage.failed
          : done
          ? LessonProjectStage.done
          : LessonProjectStage.solving,
      status: failed
          ? LessonProjectStatus.failed
          : done
          ? LessonProjectStatus.done
          : LessonProjectStatus.running,
      progress: done ? 100 : 45,
      visualWarnings: const [],
    );
  }

  @override
  Future<LegacyLessonResult> wait(
    String externalId, {
    required Future<void> Function(LessonProgressEvent event) onProgress,
  }) async {
    await onProgress(
      const LessonProgressEvent(
        stage: LessonProjectStage.solving,
        progress: 45,
        message: '正在求解',
      ),
    );
    if (failed) throw const LessonBridgeException('模型拒绝生成');
    return const LegacyLessonResult(
      externalId: 'remote-task-1',
      title: '原项目讲解',
      subject: '物理',
      html: '<html><body>legacy lesson</body></html>',
      visualWarnings: [],
    );
  }

  @override
  Future<String> html(String externalId) async =>
      '<html><body>legacy lesson</body></html>';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();


  test('仅使用图片创建原服务任务并保存 HTML', () async {
    final store = MemoryLessonStore();
    final bridge = _FakeBridge();
    final pipeline = LessonPipeline(store: store, bridge: bridge);
    final record = await pipeline.create(
      const LessonGenerationInput(
        imageDataUrl: 'data:image/png;base64,aGVsbG8=',
        refId: 8,
        refKind: 'wrongQuestion',
      ),
    );
    expect(record.status, LessonProjectStatus.done);
    expect(record.externalProjectId, 'remote-task-1');
    expect(await store.loadHtml(record.id), contains('legacy lesson'));
  });

  test('关闭页面后可根据 externalProjectId 恢复完成结果', () async {
    final store = MemoryLessonStore();
    final bridge = _FakeBridge();
    final now = DateTime.now();
    final pending = LessonProjectRecord(
      id: 'local-task-1',
      title: '待恢复讲解',
      externalProjectId: 'remote-task-1',
      status: LessonProjectStatus.running,
      stage: LessonProjectStage.solving,
      progress: 45,
      createdAt: now,
      updatedAt: now,
    );
    await store.saveRecord(pending);
    final pipeline = LessonPipeline(store: store, bridge: bridge);
    expect(await pipeline.recoverPending(), 1);
    final recovered = await store.getRecord('local-task-1');
    expect(recovered?.status, LessonProjectStatus.done);
    expect(recovered?.hasHtml, isTrue);
    expect(await store.loadHtml('local-task-1'), contains('legacy lesson'));
  });

  test('原服务失败时记录失败状态且不生成 HTML', () async {
    final store = MemoryLessonStore();
    final bridge = _FakeBridge()..failed = true;
    final pipeline = LessonPipeline(store: store, bridge: bridge);
    final record = await pipeline.create(
      const LessonGenerationInput(
        imageDataUrl: 'data:image/png;base64,aGVsbG8=',
      ),
    );
    expect(record.status, LessonProjectStatus.failed);
    expect(record.error, contains('模型拒绝生成'));
    expect(await store.loadHtml(record.id), isNull);
  });

  // 引擎各阶段超时相加最坏约 40 分钟，预算低于它就会出现“界面报任务超时、
  // 引擎其实还在正常跑”这种假失败。
  test('原服务轮询间隔为 1 秒且最长等待覆盖引擎最坏耗时', () {
    expect(LegacyLessonBridge.pollInterval, const Duration(seconds: 1));
    expect(LegacyLessonBridge.maxPollAttempts, 2400);
    final budget =
        LegacyLessonBridge.pollInterval * LegacyLessonBridge.maxPollAttempts;
    expect(budget.inMinutes, greaterThanOrEqualTo(40));
  });

  test('没有题目图片时在提交前拒绝', () async {
    final pipeline = LessonPipeline(
      store: MemoryLessonStore(),
      bridge: _FakeBridge(),
    );
    expect(
      () => pipeline.create(const LessonGenerationInput(imageDataUrl: '')),
      throwsA(isA<LessonBridgeException>()),
    );
  });

  test('只有题干文字也能创建任务（不再要求必须拍照）', () async {
    final store = MemoryLessonStore();
    final pipeline = LessonPipeline(store: store, bridge: _FakeBridge());
    final record = await pipeline.create(
      const LessonGenerationInput(
        questionText: '质量 m = 2 kg 的物块静止在水平地面上，用 8 N 的水平拉力拉它仍静止，求摩擦力。',
      ),
    );
    expect(record.status, LessonProjectStatus.done);
    expect(record.externalProjectId, 'remote-task-1');
  });

  test('既没有图片也没有题干时在提交前拒绝', () async {
    final pipeline = LessonPipeline(
      store: MemoryLessonStore(),
      bridge: _FakeBridge(),
    );
    expect(
      () => pipeline.create(const LessonGenerationInput()),
      throwsA(isA<LessonBridgeException>()),
    );
  });
}
