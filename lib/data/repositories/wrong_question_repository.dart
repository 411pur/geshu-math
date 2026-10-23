import 'dart:async';
import 'dart:convert';
import '../../../core/network/ai_json.dart';
import '../../../core/network/ai_api_client.dart';
import '../../../core/network/sse_parser.dart';
import '../../../domain/entities/wrong_question_entity.dart';
import '../../features/wrong_question/services/question_text_composer.dart';
import '../../data/datasources/local/wrong_question_datasource.dart';
import '../../data/datasources/remote/dify_response_models.dart';

/// Orchestrates the wrong-question guidance flow:
/// 1. Send question to an OpenAI-compatible chat endpoint
/// 2. Stream back guidance content
/// 3. Auto-save processed question to local DB
/// 4. Link to knowledge nodes
class WrongQuestionRepository {
  final WrongQuestionDataSource _ds;
  final AiApiClient _ai;

  WrongQuestionRepository(this._ds, this._ai);

  /// Parse AI outputs into the standard response model.
  /// outputs may have different shapes:
  /// - Direct: {guidance_result: ..., processed_question: ...}
  /// - Nested: {answer: '{"guidance_result": ...}', files: []}
  Map<String, dynamic>? _parseOutputs(Map<String, dynamic>? outputs) {
    if (outputs == null) return null;
    // Case 1: direct format
    if (outputs.containsKey('guidance_result')) return outputs;
    // Case 2: nested in 'answer' field (JSON string)
    final answer = outputs['answer'];
    if (answer is String && answer.isNotEmpty) {
      try {
        final parsed = decodeAiJsonObject(answer);
        if (parsed != null && parsed.containsKey('guidance_result')) {
          return parsed;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Submit a question and receive streaming guidance.
  /// After the stream completes, the processed question is auto-saved.
  Stream<GuidanceFlowStep> submitQuestion({
    required String questionText,
    String? imageBase64,
    String? studentStatsJson,
    bool aiSeeImage = true,
  }) async* {
    yield const GuidanceFlowStep.loading();

    final buffer = StringBuffer();
    final completer = Completer<String>();

    try {
      final stream = _ai.submitWrongQuestion(
        query: questionText,
        imageBase64: imageBase64,
        studentStatsJson: studentStatsJson,
        useImage: aiSeeImage,
      );

      await for (final event in stream) {
        switch (event) {
          case MessageChunk(:final answer):
            buffer.write(answer);
            yield GuidanceFlowStep.chunk(answer);
          case WorkflowFinished(:final outputs):
            // Parse the workflow outputs into our schema
            final parsed = _parseOutputs(outputs);
            if (parsed != null) {
              final guidResponse = WrongQuestionGuidanceResponse.fromJson(parsed);
              // Auto-save：把本次讲解结果存进错题本，供列表/详情展示与标签编辑
              final savedId = await _autoSave(guidResponse, questionText, imageBase64);
              final pqText = guidResponse.processedQuestion.questionText.isNotEmpty
                  ? guidResponse.processedQuestion.questionText
                  : questionText;
              yield GuidanceFlowStep.result(
                guidResponse.guidanceResult,
                savedId: savedId,
                questionText: pqText,
              );
            }
          case MessageEnd(:final fullAnswer):
            completer.complete(fullAnswer);
          case StreamError(:final message):
            yield GuidanceFlowStep.error(message);
            return;
        }
      }
    } catch (e) {
      yield GuidanceFlowStep.error(e.toString());
    }
  }

  Future<int?> _autoSave(
    WrongQuestionGuidanceResponse response,
    String originalText,
    String? imageBase64,
  ) async {
    final pq = response.processedQuestion;
    final now = DateTime.now().millisecondsSinceEpoch;

    final wq = WrongQuestion(
      subject: pq.subject,
      topic: pq.topic,
      questionImagePath: imageBase64,
      subTopic: pq.subTopic,
      questionText: composeQuestionTextWithOptions(pq, originalText),
      guidanceResultJson: json.encode(response.guidanceResult.toJson()),
      difficultyLevel: pq.difficultyLevel,
      keyConcept: pq.keyConcept,
      knowledgeNodeId: pq.knowledgeNodeIds.isNotEmpty ? pq.knowledgeNodeIds.first : null,
      tagsJson: json.encode(pq.tags),
      createdAt: now,
    );

    final id = _ds.insert(wq);

    // TODO: Also update the linked knowledge nodes for enrichment
    return id;
  }

  /// 保存一次讲解结果到错题本（快速版/专家版通用）。
  /// [parsed] 需包含 guidance_result 与 processed_question 两个键。
  Future<int?> saveGuidanceResponse(
    Map<String, dynamic> parsed, {
    required String originalText,
    String? imageBase64,
  }) async {
    final resp = WrongQuestionGuidanceResponse.fromJson(parsed);
    return _autoSave(
      resp,
      originalText,
      imageBase64,
    );
  }

  // ── CRUD pass-through ────────────────────────────────────

  Future<List<WrongQuestion>> getList({
    int limit = 20,
    int offset = 0,
    String? subject,
    String? topic,
    int? difficultyLevel,
  }) =>
      Future.value(_ds.getAllPaginated(
        limit: limit,
        offset: offset,
        subject: subject,
        topic: topic,
        difficultyLevel: difficultyLevel,
      ));

  Future<WrongQuestion?> getById(int id) => Future.value(_ds.getById(id));

  Future<void> delete(int id) async {
    _ds.delete(id);
  }

  Future<void> updateMastery(int id, int mastery) async {
    _ds.updateMastery(id, mastery);
  }

  Future<void> toggleFavorite(int id) async {
    _ds.toggleFavorite(id);
  }

  Future<void> updateTags(int id, List<String> tags) async {
    _ds.updateTags(id, tags);
  }

  Future<void> markPrinted(int id) async {
    _ds.markPrinted(id);
  }
}

/// Sealed state for the guidance submission flow.
sealed class GuidanceFlowStep {
  const GuidanceFlowStep();
  const factory GuidanceFlowStep.loading() = LoadingGuidanceStep;
  const factory GuidanceFlowStep.chunk(String text) = ChunkGuidanceStep;
  const factory GuidanceFlowStep.result(
    GuidanceResult result, {
    int? savedId,
    String questionText,
  }) = ResultGuidanceStep;
  const factory GuidanceFlowStep.error(String message) = ErrorGuidanceStep;
}

final class LoadingGuidanceStep extends GuidanceFlowStep {
  const LoadingGuidanceStep();
}

final class ChunkGuidanceStep extends GuidanceFlowStep {
  final String text;
  const ChunkGuidanceStep(this.text);
}

final class ResultGuidanceStep extends GuidanceFlowStep {
  final GuidanceResult result;
  final int? savedId; // 自动保存到错题本后的新错题 id，供互动讲解关联。
  final String questionText; // 原题文本（AI 提取，空则用原始输入）
  const ResultGuidanceStep(
    this.result, {
    this.savedId,
    this.questionText = '',
  });
}

final class ErrorGuidanceStep extends GuidanceFlowStep {
  final String message;
  const ErrorGuidanceStep(this.message);
}
