/// 互动讲解的「题目来源」判定。
///
/// 背景（真实故障）：学生常常只拍一张错题照片，顺手打一句"怎么写"。错因诊断走的是
/// **多模态模型**，它看得见图、也确实读出了原题（processed_question.question_text，
/// 含各选项），但生成互动讲解时用的却是学生那句提问语。于是写稿模型拿不到原题，
/// 只能根据"已有解答"把题干反推出来 —— 原题失真、选项全丢，自然也就没有逐项详解。
///
/// 这里把"转录原文优先、提问语兜底"的判定收敛到一处：可单测、可复用，页面只管调用。
library;

/// 一次视频生成该用的题目素材。
class QuestionSource {
  /// 交给视频流水线的**题目原文**（应当是原题，而不是学生的提问语）。
  final String questionText;

  /// 选择题的各选项（逐条，原文照抄；计算题为空）。
  final List<String> options;

  /// 学生的提问语：当它没被用作题干时，随素材一并说明"这不是题干"，
  /// 免得写稿模型又把"怎么写"当成题面。
  final String studentAsk;

  /// 题干来源是否可信（transcripted = 来自模型转录/学生手打的有效题目）。
  final bool trusted;

  const QuestionSource({
    required this.questionText,
    this.options = const [],
    this.studentAsk = '',
    this.trusted = true,
  });
}

/// 提问语里常见的"没有题目信息"的措辞；判定题干时先剥掉它们再看出还剩什么。
final RegExp _askPhrases = RegExp(
  '请|帮我|帮忙|麻烦|这题|这道题|此题|一下|怎么写|怎么做|咋做|如何做|怎么分析|'
  '谢谢|老师|不会做|求解答|解题思路|分析一下|看下|看看',
);

/// 题干里常见的"有题目信息"的信号：数字、单位、设问词、数学符号、题型词。
final RegExp _problemSignals = RegExp(
  r'[\d０-９]|如图|下列|正确的是|不正确|已知|求|则|计算|证明|化简|解方程|'
  '函数|集合|数列|三角|几何|向量|概率|导数|不等式|坐标|面积|周长|方程|根',
);

/// 这段文字像不像"一道题的原文"。
///
/// 判据：够长（≥12 字）且剥掉提问用语后仍有实质内容（≥10 字）且含题面信号。
/// 目的是挡住"怎么写""这题怎么做"这类提问语被当成题干。
bool looksLikeProblemText(String text) {
  final t = text.trim();
  if (t.length < 12) return false;
  final stripped = t.replaceAll(_askPhrases, '');
  if (stripped.length < 10) return false;
  return _problemSignals.hasMatch(stripped);
}

/// 决定题面文字：[scanned] 为模型从原题/图片**转录**出的原文，[typed] 为学生输入框里的文字。
///
/// 规则：
/// 1. 转录原文像题目 → 用它（**首选**，图片扫描的价值就在这里）；
/// 2. 转录原文不像题目（如模型把提问语回抄了一份）→ 学生输入像题目就用学生的；
/// 3. 两者都不像题目 → 谁有内容用谁，并如实标记 trusted=false（页面据此提示核对）；
/// 4. 学生的提问语在"没被当作题干"时随素材一起带出，避免再次污染题面。
QuestionSource resolveQuestionSource({
  required String scanned,
  required String typed,
  List<String> options = const [],
}) {
  final s = scanned.trim();
  final t = typed.trim();

  final scannedOk = looksLikeProblemText(s);
  final typedOk = looksLikeProblemText(t);

  if (scannedOk) {
    return QuestionSource(
      questionText: s,
      options: options,
      studentAsk: (t.isNotEmpty && t != s) ? t : '',
    );
  }
  if (typedOk) {
    return QuestionSource(
      questionText: t,
      options: options,
      studentAsk: (s.isNotEmpty && s != t) ? s : '',
    );
  }
  final fallback = s.isNotEmpty ? s : t;
  return QuestionSource(
    questionText: fallback,
    options: options,
    studentAsk: (t.isNotEmpty && t != fallback) ? t : '',
    // 两边都不像题目：题面不可信，页面可以据此提醒学生核对（不要装作"扫出来了"）。
    trusted: false,
  );
}
