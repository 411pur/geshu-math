import 'dart:convert';

/// 从多模态模型返回的 JSON 中取出题目文字与选项。
///
/// 兼容模型用 ```json ``` 包裹或附加说明文字的情况；解析失败则整段回退为题目文字。
/// 纯函数，不依赖任何平台 API，便于单测。
(String, List<String>) parseVisionOcrResponse(String content) {
  final raw = content.trim();
  final jsonStr = _stripCodeFence(raw);
  try {
    final d = json.decode(jsonStr) as Map<String, dynamic>;
    final text = (d['question_text'] ?? d['questionText'] ?? '').toString().trim();
    final opts =
        (d['options'] as List?)?.whereType<String>().toList() ?? const <String>[];
    return (text, opts);
  } catch (_) {
    return (raw, const <String>[]);
  }
}

String _stripCodeFence(String s) {
  final fence =
      RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
  final m = fence.firstMatch(s);
  if (m != null) return m.group(1)!.trim();
  return s;
}
