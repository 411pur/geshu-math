import 'dart:async';
import '../../../core/network/ai_api_client.dart';
import '../../../core/network/sse_parser.dart';
import '../../../domain/entities/exam_entity.dart';
import '../../data/datasources/local/exam_datasource.dart';
import '../../data/datasources/remote/dify_response_models.dart';

/// Orchestrates exam analysis:
/// 1. Send OCR text to an OpenAI-compatible chat endpoint
/// 2. Stream back analysis
/// 3. Auto-save record + question details to local DB
class ExamRepository {
  final ExamDataSource _ds;
  final AiApiClient _ai;

  ExamRepository(this._ds, this._ai);

  /// Submit exam data and receive streaming analysis.
  Stream<ExamFlowStep> submitExam({
    required String ocrText,
    String? imagePath,
  }) async* {
    yield const ExamFlowStep.loading();

    final buffer = StringBuffer();

    try {
      final stream = _ai.submitExamAnalysis(ocrText: ocrText);

      await for (final event in stream) {
        switch (event) {
          case MessageChunk(:final answer):
            buffer.write(answer);
            yield ExamFlowStep.chunk(answer);
          case WorkflowFinished(:final outputs):
            if (outputs != null) {
              final response = ExamAnalysisResponse.fromJson(outputs);
              await _autoSave(response, ocrText);
              yield ExamFlowStep.result(response.analysisResult);
            }
          case MessageEnd():
            break;
          case StreamError(:final message):
            yield ExamFlowStep.error(message);
            return;
        }
      }
    } catch (e) {
      yield ExamFlowStep.error(e.toString());
    }
  }

  Future<void> _autoSave(ExamAnalysisResponse response, String ocrText) async {
    final rec = response.processedExamRecord;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Parse date string to millis (simplified)
    final examDate = DateTime.tryParse(rec.examDate)?.millisecondsSinceEpoch ?? now;

    // Insert exam record
    final record = ExamRecord(
      examName: rec.examName,
      examDate: examDate,
      subjectsJson: rec.subjects.join(','),
      totalScore: rec.totalScore,
      studentScore: rec.studentScore,
      rawOcrText: ocrText,
      analysisResultJson: response.analysisResult.toJson().toString(),
      createdAt: now,
    );

    final recordId = _ds.insertRecord(record);

    // Insert question details
    final details = rec.questionDetails.map((d) => ExamQuestionDetail(
          examRecordId: recordId,
          questionNumber: d.questionNumber,
          topic: d.topic,
          subTopic: d.subTopic,
          maxScore: d.maxScore,
          studentScore: d.studentScore,
          isWrong: d.isWrong,
          errorType: d.errorType,
          knowledgeNodeIdsJson: d.knowledgeNodeIds.join(','),
        )).toList();

    _ds.insertDetails(details);
  }

  // ── CRUD ─────────────────────────────────────────────────

  Future<List<ExamRecord>> getHistory({int limit = 20, int offset = 0}) =>
      Future.value(_ds.getAllHistory(limit: limit, offset: offset));

  Future<ExamRecord?> getRecordById(int id) => Future.value(_ds.getRecordById(id));

  Future<List<ExamQuestionDetail>> getDetailsForRecord(int recordId) =>
      Future.value(_ds.getDetailsForRecord(recordId));
}

sealed class ExamFlowStep {
  const ExamFlowStep();
  const factory ExamFlowStep.loading() = _ExamLoading;
  const factory ExamFlowStep.chunk(String text) = _ExamChunk;
  const factory ExamFlowStep.result(AnalysisResult result) = _ExamResult;
  const factory ExamFlowStep.error(String message) = _ExamError;
}

final class _ExamLoading extends ExamFlowStep {
  const _ExamLoading();
}

final class _ExamChunk extends ExamFlowStep {
  final String text;
  const _ExamChunk(this.text);
}

final class _ExamResult extends ExamFlowStep {
  final AnalysisResult result;
  const _ExamResult(this.result);
}

final class _ExamError extends ExamFlowStep {
  final String message;
  const _ExamError(this.message);
}
