/// 从识别出的纯文本中解析选择题选项（A./B./C./D. …）。
///
/// 用于视觉 LLM 未返回结构化 options（或只想从题面文字兜底提取）的场景。
/// 仅接受从 A 开始的连续编号序列，避免误把正文里的字母当成选项。
List<String> parseMcqOptions(String text) {
  final optionRe = RegExp(r'^\s*([A-Ha-h])[\.、。)]\s*(.*)$');
  final lines = text.split('\n');
  final order = <String>[];
  final map = <String, String>{};
  String? current;

  for (final line in lines) {
    final m = optionRe.firstMatch(line);
    if (m != null) {
      current = m.group(1)!.toUpperCase();
      order.add(current);
      map[current] = (map[current] == null ? '' : '${map[current]} ') + m.group(2)!.trim();
    } else if (current != null && line.trim().isNotEmpty) {
      // 选项换行续写
      map[current] = '${map[current]} ${line.trim()}';
    }
  }

  final result = <String>[];
  for (var c = 'A'.codeUnitAt(0); c <= 'H'.codeUnitAt(0); c++) {
    final k = String.fromCharCode(c);
    if (!order.contains(k)) break;
    result.add(map[k]!);
  }
  return result;
}
