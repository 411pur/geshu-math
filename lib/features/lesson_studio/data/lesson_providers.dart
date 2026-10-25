import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../home/providers/ai_settings_provider.dart';
import '../models/lesson_project.dart';
import 'legacy_lesson_bridge.dart';
import 'lesson_ai_config.dart';
import 'lesson_pipeline.dart';
import 'lesson_repository.dart';
import 'lesson_store.dart';

final lessonStoreProvider = Provider<LessonStore>((ref) => createLessonStore());

/// 讲解服务桥接：每次构建前把浏览器可编辑的「互动讲解」板块配置同步到
/// [LessonAiConfig]（服务地址/模型），未自定义的字段保留 config.json 默认值。
final lessonBridgeProvider = Provider<LegacyLessonBridge>((ref) {
  final lesson = ref.watch(aiSettingsProvider).lesson;
  LessonAiConfig.applyBoard(lesson);
  return const LegacyLessonBridge();
});
final lessonPipelineProvider = Provider<LessonPipeline>(
  (ref) => LessonPipeline(
    store: ref.watch(lessonStoreProvider),
    bridge: ref.watch(lessonBridgeProvider),
  ),
);
final lessonRepositoryProvider = Provider<LessonRepository>(
  (ref) => LessonRepository(
    store: ref.watch(lessonStoreProvider),
    pipeline: ref.watch(lessonPipelineProvider),
  ),
);
final lessonLibraryProvider = FutureProvider<List<LessonProjectRecord>>(
  (ref) => ref.watch(lessonRepositoryProvider).list(),
);
