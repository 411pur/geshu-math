import '../../../data/datasources/remote/dify_response_models.dart';

String composeQuestionTextWithOptions(
  ProcessedQuestion question,
  String originalText,
) {
  final stem = question.questionText.trim().isNotEmpty
      ? question.questionText.trim()
      : originalText.trim();
  if (question.options.isEmpty) return stem;
  final missing = <String>[];
  for (var i = 0; i < question.options.length; i++) {
    final raw = question.options[i].trim();
    if (raw.isEmpty) continue;
    final match = RegExp(r'^\s*([A-L])[\.、:：)]\s*(.*)$').firstMatch(raw);
    final text = (match?.group(2) ?? raw).trim();
    final key = match?.group(1) ?? String.fromCharCode(65 + i);
    final normalized = '$key. $text';
    if (!stem.contains(text)) missing.add(normalized);
  }
  if (missing.isEmpty) return stem;
  return '$stem\n${missing.join('\n')}';
}
