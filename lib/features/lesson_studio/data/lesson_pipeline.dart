import 'package:uuid/uuid.dart';
import '../models/lesson_contracts.dart';
import '../models/lesson_project.dart';
import 'legacy_lesson_bridge.dart';
import 'lesson_store.dart';

typedef LessonProgressCallback = void Function(LessonProgressEvent event);

class LessonPipeline {
  final LessonStore store;
  final LegacyLessonBridge bridge;

  const LessonPipeline({required this.store, required this.bridge});

  Future<LessonProjectRecord> create(
    LessonGenerationInput input, {
    LessonProgressCallback? onProgress,
  }) async {
    if (!input.hasMaterial) {
      throw const LessonBridgeException('请先上传题目图片或填写题目文字');
    }
    final now = DateTime.now();
    final record = LessonProjectRecord(
      id: const Uuid().v4(),
      title: input.hasImage ? '拍照错题讲解' : '文字题目讲解',
      refId: input.refId,
      refKind: input.refKind,
      createdAt: now,
      updatedAt: now,
    );
    await store.saveRecord(record);
    return run(record, input, onProgress: onProgress);
  }

  Future<LessonProjectRecord> run(
    LessonProjectRecord initial,
    LessonGenerationInput input, {
    LessonProgressCallback? onProgress,
  }) async {
    var record = initial.copyWith(
      status: LessonProjectStatus.running,
      stage: LessonProjectStage.extracting,
      progress: 2,
      message: '正在提交到数学讲解生成服务',
      error: '',
      updatedAt: DateTime.now(),
    );
    await _save(record, onProgress);

    try {
      final externalId = await bridge.create(input);
      record = record.copyWith(
        externalProjectId: externalId,
        status: LessonProjectStatus.running,
        stage: LessonProjectStage.extracting,
        progress: 5,
        message: '数学讲解生成服务已接单',
        updatedAt: DateTime.now(),
      );
      await _save(record, onProgress);

      final result = await bridge.wait(
        externalId,
        onProgress: (event) async {
          record = record.copyWith(
            stage: event.stage,
            progress: event.progress,
            message: event.message,
            updatedAt: DateTime.now(),
          );
          await _save(record, onProgress);
        },
      );
      await store.saveHtml(record.id, result.html);
      record = record.copyWith(
        status: result.visualWarnings.isEmpty
            ? LessonProjectStatus.done
            : LessonProjectStatus.warning,
        stage: LessonProjectStage.done,
        progress: 100,
        title: result.title,
        subject: result.subject,
        message: result.visualWarnings.isEmpty
            ? '互动讲解 HTML 已生成'
            : '互动讲解已生成，存在视觉警告',
        visualStatus: result.visualWarnings.isEmpty
            ? LessonVisualStatus.passed
            : LessonVisualStatus.warning,
        visualWarnings: result.visualWarnings,
        hasHtml: true,
        updatedAt: DateTime.now(),
      );
      await store.saveArtifacts(record.id, {
        'source': 'legacy-node-bridge',
        'externalLessonId': result.externalId,
      });
      await _save(record, onProgress);
      return record;
    } catch (error) {
      record = record.copyWith(
        status: LessonProjectStatus.failed,
        stage: LessonProjectStage.failed,
        progress: 100,
        message: '生成失败',
        error: error.toString(),
        updatedAt: DateTime.now(),
      );
      await _save(record, onProgress);
      return record;
    }
  }

  Future<int> recoverPending() async {
    final records = await store.listRecords(limit: 500);
    var recovered = 0;
    for (final item in records) {
      if (item.externalProjectId.isEmpty ||
          (item.status != LessonProjectStatus.running &&
              item.status != LessonProjectStatus.queued)) {
        continue;
      }
      try {
        final status = await bridge.status(item.externalProjectId);
        var record = item.copyWith(
          stage: status.stage,
          progress: status.progress,
          message: status.message.isEmpty ? '正在同步数学讲解任务' : status.message,
          updatedAt: DateTime.now(),
        );
        if (status.isFailed) {
          record = record.copyWith(
            status: LessonProjectStatus.failed,
            stage: LessonProjectStage.failed,
            progress: 100,
            message: '生成失败',
            error: status.error.isEmpty ? '数学讲解任务失败' : status.error,
            updatedAt: DateTime.now(),
          );
          await store.saveRecord(record);
          continue;
        }
        if (status.isDone) {
          final html = await bridge.html(item.externalProjectId);
          await store.saveHtml(item.id, html);
          record = record.copyWith(
            status: status.visualWarnings.isEmpty
                ? LessonProjectStatus.done
                : LessonProjectStatus.warning,
            stage: LessonProjectStage.done,
            progress: 100,
            title: status.title.isEmpty ? item.title : status.title,
            subject: status.subject,
            message: status.visualWarnings.isEmpty
                ? '互动讲解 HTML 已生成'
                : '互动讲解已生成，存在视觉警告',
            visualStatus: status.visualWarnings.isEmpty
                ? LessonVisualStatus.passed
                : LessonVisualStatus.warning,
            visualWarnings: status.visualWarnings,
            hasHtml: true,
            updatedAt: DateTime.now(),
          );
          await store.saveArtifacts(item.id, {
            'source': 'legacy-node-bridge',
            'externalLessonId': item.externalProjectId,
          });
          recovered++;
        }
        await store.saveRecord(record);
      } catch (_) {
        // 服务暂不可用时保留运行中记录，下一次刷新继续恢复。
      }
    }
    return recovered;
  }

  Future<void> _save(
    LessonProjectRecord record,
    LessonProgressCallback? onProgress,
  ) async {
    await store.saveRecord(record);
    onProgress?.call(
      LessonProgressEvent(
        stage: record.stage,
        progress: record.progress,
        message: record.message,
      ),
    );
  }
}
