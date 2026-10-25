import '../models/lesson_project.dart';
import 'lesson_store_platform_io.dart'
    if (dart.library.html) 'lesson_store_web.dart'
    as platform;

abstract class LessonStore {
  Future<void> saveRecord(LessonProjectRecord record);
  Future<LessonProjectRecord?> getRecord(String id);
  Future<List<LessonProjectRecord>> listRecords({int limit = 100});
  Future<void> saveHtml(String id, String html);
  Future<String?> loadHtml(String id);
  Future<void> saveArtifacts(String id, Map<String, Object?> artifacts);
  Future<Map<String, Object?>?> loadArtifacts(String id);
  Future<LessonProjectRecord?> latestForRef(int refId, String refKind);
  Future<void> delete(String id);
}

LessonStore createLessonStore() => platform.createPlatformLessonStore();

class MemoryLessonStore implements LessonStore {
  final Map<String, LessonProjectRecord> _records = {};
  final Map<String, String> _html = {};
  final Map<String, Map<String, Object?>> _artifacts = {};

  @override
  Future<void> saveRecord(LessonProjectRecord record) async =>
      _records[record.id] = record;
  @override
  Future<LessonProjectRecord?> getRecord(String id) async => _records[id];
  @override
  Future<List<LessonProjectRecord>> listRecords({int limit = 100}) async {
    final list = _records.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list.take(limit).toList();
  }

  @override
  Future<void> saveHtml(String id, String html) async => _html[id] = html;
  @override
  Future<String?> loadHtml(String id) async => _html[id];
  @override
  Future<void> saveArtifacts(String id, Map<String, Object?> artifacts) async =>
      _artifacts[id] = artifacts;
  @override
  Future<Map<String, Object?>?> loadArtifacts(String id) async =>
      _artifacts[id];
  @override
  Future<LessonProjectRecord?> latestForRef(int refId, String refKind) async {
    final list =
        _records.values
            .where((r) => r.refId == refId && r.refKind == refKind)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<void> delete(String id) async {
    _records.remove(id);
    _html.remove(id);
    _artifacts.remove(id);
  }
}
