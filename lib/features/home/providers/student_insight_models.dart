
/// 学习画像·纯模型层（无 dart:html，可在 VM 单测）。
///
/// 三层结构：
/// - 统计层：[StudentInsight] 错题汇总（数量/掌握率/高频模块/薄弱标签）
/// - 时间线层：[StudentInsight.errorTrace] 每次讲解产生的「具体错误点」完整可追溯记录
/// - 摘要层：注入 AI 时只带 [buildPromptInsight] 生成的总结性内容（统计 + 高频错误点 TopN + 手填弱点），
///   完整时间线不进 prompt（渐进式查看信息，避免 token 膨胀）
class StudentInsight {
  final int totalWrong, weekNew, masteredRate, unmasteredRate, totalReviews;
  final List<String> topModules, weakTags;
  final String manualWeakPoints; // 学生手填薄弱点（可编辑）
  final List<Map<String, dynamic>> errorTrace; // 具体错误点时间线（完整、可追溯）
  final int updatedAt;

  const StudentInsight({
    this.totalWrong = 0,
    this.weekNew = 0,
    this.masteredRate = 0,
    this.unmasteredRate = 0,
    this.totalReviews = 0,
    this.topModules = const [],
    this.weakTags = const [],
    this.manualWeakPoints = '',
    this.errorTrace = const [],
    this.updatedAt = 0,
  });

  bool get isEmpty => totalWrong == 0 && topModules.isEmpty && weakTags.isEmpty;

  factory StudentInsight.fromJson(Map<String, dynamic> j) => StudentInsight(
        totalWrong: (j['total_wrong'] as num?)?.toInt() ?? 0,
        weekNew: (j['week_new'] as num?)?.toInt() ?? 0,
        masteredRate: (j['mastered_rate'] as num?)?.toInt() ?? 0,
        unmasteredRate: (j['unmastered_rate'] as num?)?.toInt() ?? 0,
        totalReviews: (j['total_reviews'] as num?)?.toInt() ?? 0,
        topModules: (j['top_modules'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        weakTags: (j['weak_tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        manualWeakPoints: j['manual_weak_points'] as String? ?? '',
        errorTrace: (j['error_trace'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            const [],
        updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'total_wrong': totalWrong,
        'week_new': weekNew,
        'mastered_rate': masteredRate,
        'unmastered_rate': unmasteredRate,
        'total_reviews': totalReviews,
        'top_modules': topModules,
        'weak_tags': weakTags,
        'manual_weak_points': manualWeakPoints,
        'error_trace': errorTrace,
        'updated_at': updatedAt,
      };

  // ── 摘要层：渐进式注入 AI 的总结性内容 ──────────────────

  /// 错误点指纹聚合：指纹 → 出现次数（按最新时间排序）。
  Map<String, int> errorFreq() {
    final freq = <String, int>{};
    for (final e in errorTrace) {
      final f = e['fingerprint']?.toString();
      if (f != null && f.isNotEmpty) freq[f] = (freq[f] ?? 0) + 1;
    }
    return freq;
  }

  /// 供 AI 参考的总结性画像文本（不注入完整时间线）。
  /// [limit] 控制错误点摘要条数（默认 5）。
  String buildPromptInsight({int limit = 5, String? statsJson}) {
    final parts = <String>[];
    if (statsJson != null && statsJson.isNotEmpty) {
      parts.add('【学生错题概况（仅统计信息）】\n$statsJson');
    }
    // 高频具体错误点：让 AI 在新题命中同类错误时主动提醒
    final freq = errorFreq();
    if (freq.isNotEmpty) {
      final top = freq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final lines = top.take(limit).map((e) {
        final entry = errorTrace.lastWhere(
          (t) => t['fingerprint']?.toString() == e.key,
          orElse: () => const {},
        );
        final desc = (entry['key_point']?.toString() ?? e.key).trim();
        return '- $desc —— 已出现 ${e.value} 次';
      }).join('\n');
      parts.add('【学生历史具体错误点（请在新题命中同类错误时在讲解开头提醒学生，可引用此摘要）】\n$lines');
    }
    if (manualWeakPoints.isNotEmpty) {
      parts.add('【学生自述薄弱点】\n$manualWeakPoints');
    }
    return parts.join('\n\n');
  }
}

/// 记录一条具体错误点时间线条目。
Map<String, dynamic> buildErrorTraceEntry({
  required String source, // expert / quick
  required String questionText,
  Map<String, dynamic>? explanation,
  Map<String, dynamic>? processedQuestion,
  List<String>? studentDoubts,
  int? timestamp,
}) {
  final exp = explanation ?? const <String, dynamic>{};
  final pq = processedQuestion ?? const <String, dynamic>{};
  final errorTypeRaw = exp['error_type']?.toString() ?? '';
  final errorType = errorTypeRaw.isEmpty ? '其他' : errorTypeRaw; // 展示兜底
  final subTopic = pq['sub_topic']?.toString() ?? '';
  final keyConcept = pq['key_concept']?.toString() ?? '';
  // 指纹：子考点|错因类型|核心概念（只拼非空部分，全空 → 未分类），跨题聚合同一类具体错误
  final fingerprintParts = [subTopic, errorTypeRaw, keyConcept]
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final fingerprint = fingerprintParts.isEmpty ? '未分类' : fingerprintParts.join('|');
  // 具体错误描述：优先取 AI 错因分析摘要，否则取标题/子考点
  final keyPointRaw = exp['error_analysis']?.toString().trim() ?? '';
  final keyPoint = keyPointRaw.isNotEmpty
      ? _truncate(keyPointRaw, 60)
      : _truncate('$subTopic${keyConcept.isNotEmpty ? '·$keyConcept' : ''}', 60);
  // 学生疑问点：本次追问中学生的回答/疑问
  final doubt = studentDoubts != null && studentDoubts.isNotEmpty
      ? _truncate(studentDoubts.join('；'), 80)
      : '';
  return {
    'ts': timestamp ?? DateTime.now().millisecondsSinceEpoch,
    'source': source,
    'question': _truncate(questionText.replaceAll(RegExp(r'\s+'), ' '), 60),
    'sub_topic': subTopic,
    'error_type': errorType,
    'key_concept': keyConcept,
    'key_point': keyPoint,
    'doubt': doubt,
    'fingerprint': fingerprint.isEmpty ? '未分类' : fingerprint,
  };
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';
