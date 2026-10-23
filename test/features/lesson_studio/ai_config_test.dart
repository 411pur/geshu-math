import 'package:flutter_test/flutter_test.dart';
import 'package:geshu_math/features/home/providers/ai_settings_models.dart';
import 'package:geshu_math/features/lesson_studio/data/lesson_ai_config.dart';

void main() {
  const defaults = AiSettings(
    baseUrl: 'http://127.0.0.1:8124/v1',
    apiKey: 'proxy-managed',
    model: 'new-model',
    reasoningModel: 'reasoning-model',
    visionModel: 'vision-model',
  );
  test('empty browser fields inherit updated file defaults', () {
    expect(const AiSettings().resolve(defaults).model, 'new-model');
    expect(
      const AiSettings().resolve(defaults).reasoningModel,
      'reasoning-model',
    );
    expect(defaults.overrides(defaults)['model'], '');
    expect(defaults.overrides(defaults)['reasoningModel'], '');
  });
  test('managed mode discards stale browser credentials and endpoints', () {
    final result = const AiSettings(
      apiKey: 'old-secret',
      baseUrl: 'https://old.invalid',
      model: 'old',
      qa: BoardAiConfig(apiKey: 'board-secret'),
    ).resolve(defaults, managed: true);
    expect(result.apiKey, 'proxy-managed');
    expect(result.model, 'new-model');
    expect(result.reasoningModel, 'reasoning-model');
    expect(result.qa.apiKey, '');
  });
  test('resetting lesson override restores file address', () {
    LessonAiConfig.apply({
      'externalLessonBridgeUrl': 'http://127.0.0.1:8124',
      'model': 'file-model',
    });
    LessonAiConfig.applyBoard(
      const BoardAiConfig(baseUrl: 'http://127.0.0.1:9999', model: 'custom'),
    );
    LessonAiConfig.applyBoard(const BoardAiConfig());
    expect(LessonAiConfig.externalLessonBridgeUrl, 'http://127.0.0.1:8124');
    expect(LessonAiConfig.model, 'file-model');
  });
}
