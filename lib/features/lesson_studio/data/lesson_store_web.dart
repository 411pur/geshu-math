import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../models/lesson_project.dart';
import 'lesson_store.dart';

LessonStore createPlatformLessonStore() => IndexedDbLessonStore();

class IndexedDbLessonStore implements LessonStore {
  static const _dbName = 'geshu_math_lesson_studio';
  static const _records = 'lesson_records';
  static const _htmlStore = 'lesson_html';
  static const _artifactStore = 'lesson_artifacts';
  Future<web.IDBDatabase>? _dbFuture;

  Future<web.IDBDatabase> _db() => _dbFuture ??= _open();

  Future<web.IDBDatabase> _open() async {
    final request = web.window.indexedDB.open(_dbName, 1);
    unawaited(
      web.EventStreamProviders.upgradeNeededEvent.forTarget(request).first.then(
        (_) {
          final db = request.result as web.IDBDatabase;
          if (!db.objectStoreNames.contains(_records)) {
            db.createObjectStore(
              _records,
              web.IDBObjectStoreParameters(keyPath: 'id'.toJS),
            );
          }
          if (!db.objectStoreNames.contains(_htmlStore)) {
            db.createObjectStore(
              _htmlStore,
              web.IDBObjectStoreParameters(keyPath: 'id'.toJS),
            );
          }
          if (!db.objectStoreNames.contains(_artifactStore)) {
            db.createObjectStore(
              _artifactStore,
              web.IDBObjectStoreParameters(keyPath: 'id'.toJS),
            );
          }
        },
      ),
    );
    await web.EventStreamProviders.successEvent.forTarget(request).first;
    return request.result as web.IDBDatabase;
  }

  Future<dynamic> _request(web.IDBRequest request) async {
    await web.EventStreamProviders.successEvent.forTarget(request).first;
    return request.result?.dartify();
  }

  Future<web.IDBObjectStore> _store(
    web.IDBDatabase db,
    String name,
    String mode,
  ) async => db.transaction(name.toJS, mode).objectStore(name);

  @override
  Future<void> saveRecord(LessonProjectRecord record) async {
    final db = await _db();
    await _request(
      (await _store(db, _records, 'readwrite')).put(record.toJson().jsify()),
    );
  }

  @override
  Future<LessonProjectRecord?> getRecord(String id) async {
    final db = await _db();
    final raw = await _request(
      (await _store(db, _records, 'readonly')).get(id.toJS),
    );
    return raw is Map
        ? LessonProjectRecord.fromJson(Map<String, dynamic>.from(raw))
        : null;
  }

  @override
  Future<List<LessonProjectRecord>> listRecords({int limit = 100}) async {
    final db = await _db();
    final raw = await _request(
      (await _store(db, _records, 'readonly')).getAll(),
    );
    final list =
        (raw as List)
            .whereType<Map>()
            .map(
              (e) => LessonProjectRecord.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list.take(limit).toList();
  }

  @override
  Future<void> saveHtml(String id, String htmlText) async {
    final db = await _db();
    await _request(
      (await _store(
        db,
        _htmlStore,
        'readwrite',
      )).put({'id': id, 'html': htmlText}.jsify()),
    );
  }

  @override
  Future<String?> loadHtml(String id) async {
    final db = await _db();
    final raw = await _request(
      (await _store(db, _htmlStore, 'readonly')).get(id.toJS),
    );
    return raw is Map ? raw['html']?.toString() : null;
  }

  @override
  Future<void> saveArtifacts(String id, Map<String, Object?> artifacts) async {
    final db = await _db();
    await _request(
      (await _store(
        db,
        _artifactStore,
        'readwrite',
      )).put({'id': id, 'artifacts': artifacts}.jsify()),
    );
  }

  @override
  Future<Map<String, Object?>?> loadArtifacts(String id) async {
    final db = await _db();
    final raw = await _request(
      (await _store(db, _artifactStore, 'readonly')).get(id.toJS),
    );
    if (raw is! Map || raw['artifacts'] is! Map) return null;
    return Map<String, Object?>.from(raw['artifacts'] as Map);
  }

  @override
  Future<LessonProjectRecord?> latestForRef(int refId, String refKind) async {
    for (final record in await listRecords(limit: 500)) {
      if (record.refId == refId && record.refKind == refKind) return record;
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {
    final db = await _db();
    await _request((await _store(db, _records, 'readwrite')).delete(id.toJS));
    await _request((await _store(db, _htmlStore, 'readwrite')).delete(id.toJS));
    await _request(
      (await _store(db, _artifactStore, 'readwrite')).delete(id.toJS),
    );
  }
}
