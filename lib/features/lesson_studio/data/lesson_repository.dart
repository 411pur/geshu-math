import '../models/lesson_contracts.dart';
import '../models/lesson_project.dart';
import 'lesson_pipeline.dart';
import 'lesson_store.dart';

class LessonRepository {
  final LessonStore store;
  final LessonPipeline pipeline;
  const LessonRepository({required this.store, required this.pipeline});

  Future<LessonProjectRecord> create(
    LessonGenerationInput input, {
    LessonProgressCallback? onProgress,
  }) => pipeline.create(input, onProgress: onProgress);
  Future<LessonProjectRecord> regenerate(
    LessonProjectRecord record,
    LessonGenerationInput input, {
    LessonProgressCallback? onProgress,
  }) => pipeline.run(record, input, onProgress: onProgress);
  Future<List<LessonProjectRecord>> list({int limit = 100}) async {
    await pipeline.recoverPending();
    return store.listRecords(limit: limit);
  }

  Future<LessonProjectRecord?> get(String id) async {
    await pipeline.recoverPending();
    return store.getRecord(id);
  }

  Future<String?> loadHtml(String id) => store.loadHtml(id);
  Future<Map<String, Object?>?> loadArtifacts(String id) =>
      store.loadArtifacts(id);
  Future<LessonProjectRecord?> latestForRef(int refId, String refKind) =>
      store.latestForRef(refId, refKind);
  Future<void> delete(String id) => store.delete(id);
}
