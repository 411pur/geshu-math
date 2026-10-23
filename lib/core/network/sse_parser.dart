import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'ai_json.dart';

sealed class DifyStreamEvent {
  const DifyStreamEvent();
}

final class MessageChunk extends DifyStreamEvent {
  final String answer;
  const MessageChunk(this.answer);
}

final class WorkflowFinished extends DifyStreamEvent {
  final Map<String, dynamic>? outputs;
  const WorkflowFinished({this.outputs});
}

final class MessageEnd extends DifyStreamEvent {
  final String fullAnswer;
  const MessageEnd(this.fullAnswer);
}

final class StreamError extends DifyStreamEvent {
  final String message;
  const StreamError(this.message);
}

class SseParser {
  SseParser._();

  /// Parse SSE from a full string response (blocking mode).
  static List<DifyStreamEvent> parseBlocking(String raw) {
    final events = <DifyStreamEvent>[];
    String fullAnswer = '';
    
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
      
      try {
        final data = json.decode(trimmed.substring(5).trim()) as Map<String, dynamic>;
        switch (data['event']) {
          case 'message':
            final answer = data['answer'] as String? ?? '';
            fullAnswer += answer;
            String text = answer;
try {
                final parsed = decodeAiJson(answer);
                if (parsed is Map) {
                  if (parsed.containsKey('answer')) {
                    text = parsed['answer'] as String? ?? answer;
                  } else if (parsed.containsKey('guidance_result')) {
                    text =
                        (parsed['guidance_result'] as Map)['analysis'] as String? ??
                            '';
                  }
                }
              } catch (_) {}
              events.add(MessageChunk(text));
          case 'workflow_finished':
            events.add(WorkflowFinished(outputs: data['data']?['outputs'] is Map ? Map.from(data['data']['outputs']) : null));
          case 'message_end':
            try {
              final endParsed = decodeAiJson(fullAnswer);
              if (endParsed is Map<String, dynamic>) {
                events.add(WorkflowFinished(outputs: endParsed));
              }
            } catch (_) {}
            events.add(MessageEnd(fullAnswer));
            return events;
          case 'error':
            events.add(StreamError(data['message'] as String? ?? 'Unknown error'));
            return events;
        }
      } catch (e) {
        events.add(StreamError('SSE parse: $e'));
      }
    }
    return events;
  }

  /// Parse OpenAI-compatible SSE (Aliyun DashScope compatible-mode).
  ///
  /// 契约要点（与 Dify 不同）：
  /// - 每行 `data: {json}`，无 `[DONE]` 结束符
  /// - 文本增量在 `choices[0].delta.content`
  /// - 结束：`choices[0].finish_reason != null`，或出现 `choices: []` 的 usage chunk
  /// - 流结束后尝试把累积完整输出解析为 JSON → WorkflowFinished(outputs)
  static Stream<DifyStreamEvent> parseOpenAiStream(ResponseBody body) async* {
    final buffer = StringBuffer();
    var done = false;
    try {
      await for (final chunk in body.stream) {
        final text = utf8.decode(chunk);
        for (final line in text.split('\n')) {
          if (done) break;
          final trimmed = line.trim();
          if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
          final payload = trimmed.substring(5).trim();
          if (payload.isEmpty || payload == '[DONE]') continue;
          try {
            final obj = json.decode(payload) as Map<String, dynamic>;
            final choices = obj['choices'] as List? ?? [];
            if (choices.isEmpty) continue; // usage-only chunk
            final first = choices[0] as Map<String, dynamic>;
            final delta = first['delta'] as Map<String, dynamic>? ?? const {};
            final content = delta['content'];
            if (content is String && content.isNotEmpty) {
              buffer.write(content);
              yield MessageChunk(content);
            }
            final finishReason = first['finish_reason'];
            if (finishReason != null) {
              done = true;
              break;
            }
          } catch (_) {
            // 忽略无法解析的行
          }
        }
      }
    } catch (e) {
      yield StreamError('SSE parse: $e');
      return;
    }
    final full = buffer.toString();
    // 数学讲解含 LaTeX，模型可能写出非法 JSON 转义（\frac 而不是 \\frac），
    // 交给 decodeAiJson 做一次容错修复。
    final parsed = decodeAiJson(full);
    if (parsed is Map<String, dynamic>) {
      yield WorkflowFinished(outputs: parsed);
    }
    yield MessageEnd(full);
  }

  /// Parse SSE from a streaming response body (streaming mode).
  static Stream<DifyStreamEvent> parseStream(ResponseBody body) async* {
    String fullAnswer = '';
    
    await for (final chunk in body.stream) {
      final text = utf8.decode(chunk);
      for (final line in text.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
        if (trimmed == 'data: ping' || trimmed == 'data: [DONE]') continue;

        debugPrint('[SSE] $trimmed');        try {
          final data = json.decode(trimmed.substring(5).trim()) as Map<String, dynamic>;
          switch (data['event']) {
            case 'message':
              final answer = data['answer'] as String? ?? '';
              fullAnswer += answer;
              String text = answer;
try {
                    final parsed = decodeAiJson(answer);
                    if (parsed is Map) {
                      if (parsed.containsKey('answer')) {
                        text = parsed['answer'] as String? ?? answer;
                      } else if (parsed.containsKey('guidance_result')) {
                        text = (parsed['guidance_result'] as Map)['analysis']
                                as String? ??
                            '';
                      }
                    }
                  } catch (_) {}
                  yield MessageChunk(text);
            case 'workflow_finished':
              yield WorkflowFinished(outputs: data['data']?['outputs'] is Map ? Map.from(data['data']['outputs']) : null);
            case 'message_end':
              try {
                final parsed = decodeAiJson(fullAnswer);
                if (parsed is Map<String, dynamic>) {
                  yield WorkflowFinished(outputs: parsed);
                }
              } catch (e) {
                yield StreamError('Parse end: $e');
              }
              yield MessageEnd(fullAnswer);
              return;
            case 'error':
              yield StreamError(data['message'] as String? ?? 'Unknown error');
              return;
          }
        } catch (_) {}
      }
    }
  }
}