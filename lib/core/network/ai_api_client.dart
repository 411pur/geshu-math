import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/api_endpoints.dart';
import '../error/app_exception.dart';
import '../../features/home/providers/ai_settings_provider.dart';
import 'sse_parser.dart';

/// 调用任意 OpenAI 兼容接口（`/chat/completions`）的客户端。
///
/// 单次 LLM 调用 + 结构化系统提示词直接产出所需 JSON；服务商与模型由配置决定，
/// 换 `baseUrl` / `apiKey` / `model` 即可切换，无需改代码。
///
/// 配置来源（按优先级）：
/// 1. [settings]（来自「我的 → 设置」的个人配置，存 localStorage）
/// 2. web/config.json 加载进 [ApiEndpoints] 的默认值
/// 3. 内置默认提示词（当板块未自定义 prompt 时）
///
/// 保持输出事件与 [DifyStreamEvent] 兼容，repositories/页面无需改动。
class AiApiClient {
  final Dio _dio;
  final AiSettings settings;
  AiApiClient({required Dio dio, AiSettings? settings})
      : _dio = dio,
        settings = settings ?? AiSettings.defaults();

  // ── 配置解析（板块覆盖 → 全局 → ApiEndpoints 默认） ──────
  /// 取第一个"可用"的候选值：跳过空串与 YOUR_ 占位符。
  String _pick(List<String> candidates, String fallback) {
    for (final candidate in candidates) {
      final v = candidate.trim();
      if (v.isNotEmpty && !ApiEndpoints.isPlaceholder(v)) return v;
    }
    return fallback;
  }

  String _url(BoardAiConfig board) =>
      _pick([board.baseUrl, settings.baseUrl], ApiEndpoints.baseUrl);

  String _key(BoardAiConfig board) =>
      _pick([board.apiKey, settings.apiKey], ApiEndpoints.apiKey);

  String _model(BoardAiConfig board) => _pick(
        [board.model, settings.model],
        ApiEndpoints.model,
      );

  /// 多模态模型：板块未单独配置时回落到全局 visionModel。
  String _visionModel() {
    final v = settings.visionModel.trim();
    return v.isNotEmpty ? v : ApiEndpoints.visionModel;
  }

  /// 板块提示词：自定义优先，空则用内置默认。
  String _prompt(BoardAiConfig board, String builtin) =>
      board.prompt.trim().isNotEmpty ? board.prompt.trim() : builtin;

  /// 流式调用 OpenAI 兼容接口的 chat/completions。
  ///
  /// [boardKey] 为板块标识（wrongQuestion/expert/followUp/exam/qa/report）。
  /// 当 [ApiEndpoints.useServerPrompts] 开启且该板块未自定义 prompt 时，不再
  /// 发送内置系统提示词，改由网关按 `X-Board` 注入；自定义 prompt 则带
  /// `X-Custom-Prompt: 1` 放行，保证「设置」里的个性化仍然生效。
  Stream<DifyStreamEvent> _chatStream({
    required List<Map<String, dynamic>> messages,
    required BoardAiConfig board,
    String? boardKey,
    bool jsonMode = false,
    String? model,
    double temperature = 0.7,
  }) async* {
    final hasCustomPrompt = board.prompt.trim().isNotEmpty;
    final offloadPrompt =
        ApiEndpoints.useServerPrompts && boardKey != null && !hasCustomPrompt;
    final effectiveMessages = offloadPrompt
        ? messages.where((m) => m['role'] != 'system').toList()
        : messages;
    final body = <String, dynamic>{
      'model': model ?? _model(board),
      'messages': effectiveMessages,
      'stream': true,
      'temperature': temperature,
      if (jsonMode) 'response_format': {'type': 'json_object'},
    };
    final key = _key(board);
    final url = _url(board);
    // 服务端托管提示词时，Key 由网关持有，前端空 Key 也允许发出。
    if (!ApiEndpoints.useServerPrompts) {
      if (ApiEndpoints.isPlaceholder(key)) {
        throw const AiApiException(
          '尚未配置 AI 服务：请在「我的 → 设置」里填写 Base URL、模型名与 '
          'API Key，或在 web/config.json 的 ai 段配置 '
          'apiBaseUrl / apiKey / model，配置后刷新页面即可。',
        );
      }
      if (url.isEmpty) {
        throw const AiApiException(
          '尚未配置 AI 接口地址：请在「我的 → 设置」或 web/config.json 中填写 '
          'apiBaseUrl。',
        );
      }
      if ((model ?? _model(board)).trim().isEmpty) {
        throw const AiApiException(
          '尚未配置模型名称：请在「我的 → 设置」或 web/config.json 中填写 '
          'model（图片识别另需 visionModel）。',
        );
      }
    }
    final headerMap = <String, dynamic>{
      // 占位/空 Key 时发一个哨兵值，网关一律忽略客户端 Key。
      'Authorization':
          'Bearer ${ApiEndpoints.isPlaceholder(key) ? 'proxy-managed' : key}',
    };
    if (boardKey != null) headerMap['X-Board'] = boardKey;
    if (hasCustomPrompt) headerMap['X-Custom-Prompt'] = '1';
    final q = messages.isNotEmpty
        ? (messages.last['content'].toString().length > 40 ? messages.last['content'].toString().substring(0, 40) : messages.last['content'].toString())
        : '';
    debugPrint('[AI] POST $q');
    try {
      final r = await _dio.post(
        '$url/chat/completions',
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: headerMap,
        ),
      );
      debugPrint('[AI] response ${r.statusCode}');
      yield* SseParser.parseOpenAiStream(r.data as ResponseBody);
    } on DioException catch (e) {
      String? msg;
      try {
        final errBody = e.response?.data;
        if (errBody is Map) {
          final err = errBody['error'];
          if (err is Map) msg = err['message']?.toString();
        }
      } catch (_) {}
      debugPrint('[AI] ERROR: ${e.type} ${e.message} ${msg ?? ""}');
      throw AiApiException(msg ?? '${e.type}: ${e.message ?? "连接失败"}');
    }
  }

  // ── 错题指导（错题DNA） ────────────────────────────────
  Stream<DifyStreamEvent> submitWrongQuestion({
    required String query,
    String? imageBase64,
    String? studentStatsJson,
    bool useImage = true,
  }) async* {
    final board = settings.wrongQuestion;
    final userParts = <Map<String, dynamic>>[];
    if (query.isNotEmpty) {
      userParts.add({'type': 'text', 'text': query});
    }
    if (useImage && imageBase64 != null && imageBase64.isNotEmpty) {
      userParts.add({'type': 'image_url', 'image_url': {'url': imageBase64}});
    }
    if (studentStatsJson != null && studentStatsJson.isNotEmpty) {
      userParts.add({
        'type': 'text',
        'text': '【学生错题概况（仅统计信息，请结合讲解）】\n$studentStatsJson',
      });
    }
    final userContent = userParts.length == 1 ? userParts.first['text'] as String : userParts;
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _prompt(board, _wrongQuestionSystemPrompt)},
      {'role': 'user', 'content': userContent},
    ];
    // 含图片时用多模态模型（板块 model 未自定义时用全局 visionModel）
    final needVision = imageBase64 != null && imageBase64.isNotEmpty;
    final visionModel = _visionModel();
    yield* _chatStream(
      messages: messages,
      board: board,
      boardKey: 'wrongQuestion',
      jsonMode: true,
      model: needVision ? visionModel : _model(board),
      temperature: 0.3,
    );
  }

  // ── 错题指导·专家版（多轮循环对话） ────────────────────
  /// 专家模式：多轮追问闭环。页面维护完整 [messages] 历史（不含 system），
  /// 首轮为 user(题目文本+图片+学生画像)，之后按 [user回答, assistant追问, ...] 交替。
  /// 每轮调用 AI 判断 stage=asking（继续追问）或 stage=explaining（进入讲解）。
  Stream<DifyStreamEvent> submitExpertRound({
    required List<Map<String, dynamic>> messages,
  }) async* {
    final board = settings.wrongQuestion;
    // 仅当历史中真实包含 image_url 消息时才用多模态模型（List 里只有纯文本时仍可用文本模型）
    final needVision = messages.any((m) {
      final c = m['content'];
      return c is List && c.any((p) => p is Map && p['type'] == 'image_url');
    });
    final visionModel = _visionModel();
    yield* _chatStream(
      messages: [
        {'role': 'system', 'content': _prompt(board, _expertSystemPrompt)},
        ...messages,
      ],
      board: board,
      boardKey: 'expert',
      jsonMode: true,
      model: needVision ? visionModel : _model(board),
      temperature: 0.4,
    );
  }

  // ── 错题讲解后继续追问（快速版/专家版共用） ──────────────
  /// [messages] 为完整历史（不含 system），页面负责组装题目+讲解+追问的上下文。
  Stream<DifyStreamEvent> followUpWrongQuestion({
    required List<Map<String, dynamic>> messages,
  }) async* {
    final board = settings.wrongQuestion;
    yield* _chatStream(
      messages: [
        {'role': 'system', 'content': _prompt(board, _followUpSystemPrompt)},
        ...messages,
      ],
      board: board,
      boardKey: 'followUp',
      temperature: 0.5,
    );
  }

  /// 题目图片识别：用多模态模型把数学题图片转写为题目文本（供文本模型生成讲解）。
  /// 返回 null 表示识别失败（调用方回退到图片直发）。
  Future<String?> ocrQuestionImage(String base64) async {
    final board = settings.wrongQuestion;
    final model = _visionModel();
    try {
      final r = await _dio.post(
        '${_url(board)}/chat/completions',
        data: {
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': '请把这张数学题目图片中的题目原文完整准确地转写出来。要求：保留公式、上下标、根号、分式、不等号与几何图形标注；公式尽量用 LaTeX 书写（如 x^2 写作 \$x^2\$，分数写作 \$\\frac{a}{b}\$）；保留选项 ABCD 与数值单位。只输出题目文本，不要解释、不要作答。'},
                {'type': 'image_url', 'image_url': {'url': base64}},
              ],
            },
          ],
          'temperature': 0.1,
        },
        options: Options(headers: {'Authorization': 'Bearer ${_key(board)}'}),
      );
      final data = r.data;
      if (data is Map) {
        final content = (data['choices'] as List?)?.cast<Map>().firstOrNull?['message']?['content'];
        if (content is String && content.trim().isNotEmpty) return content.trim();
      }
    } catch (e) {
      debugPrint('[AI] OCR 失败: $e');
    }
    return null;
  }

  // ── 考试分析（试卷 OCR → 分析） ────────────────────────
  Stream<DifyStreamEvent> submitExamAnalysis({required String ocrText}) async* {
    final board = settings.exam;
    yield* _chatStream(
      messages: [
        {'role': 'system', 'content': _prompt(board, _examSystemPrompt)},
        {'role': 'user', 'content': ocrText},
      ],
      board: board,
      boardKey: 'exam',
      jsonMode: true,
      temperature: 0.3,
    );
  }

  // ── 智能问答（通用对话） ────────────────────────────────
  Stream<DifyStreamEvent> sendQaMessage({required String query, String? conversationId}) async* {
    final board = settings.qa;
    yield* _chatStream(
      messages: [
        {'role': 'system', 'content': _prompt(board, _qaSystemPrompt)},
        {'role': 'user', 'content': query},
      ],
      board: board,
      boardKey: 'qa',
      temperature: 0.7,
    );
  }

  // ── 学习报告 ────────────────────────────────────────────
  Stream<DifyStreamEvent> sendReportMessage({
    required String studentDataJson,
    int days = 7,
    String grade = '',
  }) async* {
    final board = settings.report;
    final userContent = '年级: $grade\n统计天数: $days 天\n\n【错题数据】\n$studentDataJson';
    yield* _chatStream(
      messages: [
        {'role': 'system', 'content': _prompt(board, _reportSystemPrompt)},
        {'role': 'user', 'content': userContent},
      ],
      board: board,
      boardKey: 'report',
      temperature: 0.4,
    );
  }

  // ── 内置默认提示词（板块未自定义时的兜底） ──────────────
  //
  // 说明：以下提示词全部面向初高中数学教学。公式一律使用 LaTeX（渲染层
  // texToUnicode 会把它转成学生可读的 Unicode 数学写法），正文使用 Markdown。
  // 注意：JSON 字符串值中的反斜杠必须按 JSON 规范转义（\\frac），否则会破坏解析。

  /// 专家版循环对话提示词：多轮追问（选择题形式）→ 信息充足 → 对症讲解。
  /// 追问必须是选择题而非开放式提问——学生本来就不会，开放问题只会让他更懵。
  static const String _expertSystemPrompt = r'''
你是「格数至理」专家诊断老师，一位带过多年初三与高三的数学特级教师。与快速版「一问一答」不同，你不急着给答案，而是像一对一诊室一样，先通过多轮选择题把学生的卡点问清楚，再给出针对性讲解。

【执行规则（重要）】
1. 多轮诊断由**前端按决策树自动分段驱动**：每一轮你会收到 user 消息末尾的【本轮任务：...】指令——它给出当前节点该问的问题（含选项），或指示"到达叶子节点，立即输出 stage=explaining 讲解"。**严格按该指令执行，不要替前端预判后续步骤、不要自行跳层、不要自行更换问题**。
2. 追问一律用选择题（3-5 个口语化选项，贴近学生认知），让学生一键认领卡点，例如"不知道从哪下手 / 公式记不清 / 算错了 / 看错题了 / 分类讨论漏了一种"。
3. 禁止重复已经问过的任何问题（哪怕换个说法）；最多 6 轮。
4. 当指令标注"到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问"时：直接进入完整讲解，不要再追问；讲解内容严格按指令标注的重点组织。

【讲解模板】严格按「错题订正」标准模板输出（先给正确结果 → 分步解析 → 错因剖析 → 知识点回顾 → 易错警示 → 变式训练 → 档案信息）：
   - 判定错因类型（严格归为四分类：概念混淆 / 计算失误 / 审题偏差 / 方法误选，都不典型写「其他」）
   - 输出以下 7 部分，整体 450-700 字：
     ① 本题正确答案（30-50 字，含取值范围、定义域或答句）
     ② 标准分步解析【核心主体】（180-280 字）：圈画关键条件 → 明确解题思路（几何辅助线 / 代数变形 / 函数建模 / 分类讨论 / 数形结合）→ 写出所用定理或原始公式 → 代入或变形 → 分步推导得结果，每一步注明依据
     ③ 精准错因分析（90-140 字）：拒绝「粗心」，从概念理解 / 公式适用条件 / 审题 / 计算与化简层面逐条定位
     ④ 核心知识点回顾（70-110 字）：必考定义、定理、公式及适用条件（如判别式、定义域、基本不等式取等条件、零点存在定理）
     ⑤ 本题易错警示（40-70 字）
     ⑥ 举一反三·变式训练（40-60 字）：同考点变式题，只出题不给答案
     ⑦ 错题基础档案信息（原题来源 + 学生原过程与错误答案）
   - 针对学生选择的卡点先一句共情再讲；根据学生画像（高频错题模块、薄弱标签）调整讲解深度与例题难度。

【公式与排版（硬性）】
- 全部数学式子使用 LaTeX：行内公式 $...$，独立成行的公式 $$...$$；分数用 \frac，根号用 \sqrt，上下标用 ^ 与 _，希腊字母用 \alpha、\theta 等。
- 严禁用纯文本写 x^2、sqrt(x)、a/b、x1、x2 这类形式；也不要用反引号包裹公式（反引号在界面上是代码样式，公式要以 LaTeX 形式给出才能正确渲染）。
- 正文用 Markdown：步骤用有序列表、要点用无序列表、小节用 ### 标题、关键结论与易错点用 **加粗**；禁止图片与链接。
- 中文与公式之间留一个空格；只写数学环境内的内容，不要出现 \usepackage、\begin{document} 等宏包命令。
- 输出 JSON 时，字符串值里的反斜杠必须按 JSON 规范转义：写成 \\frac、\\sqrt、\\alpha（即 JSON 中的两个反斜杠代表一个 LaTeX 反斜杠）。

【step_analysis 期望效果示例（照此风格排版）】
- **关键条件**：$a=1$，$b=-4$，$c=3$，求方程 $x^2-4x+3=0$ 的两根
- **解题思路**：因式分解，把二次三项式拆成两个一次因式的积
- **原始公式**：$$x^2-4x+3=(x-1)(x-3)$$
- **求解**：$x-1=0$ 或 $x-3=0$
- **结论**：**方程的两根为 $x_1=1$、$x_2=3$**

【输出格式】输出严格的 JSON 对象（不要输出任何多余文字或 Markdown 代码块）：
{
  "stage": "asking" 或 "explaining",
  "round": 当前对话轮次（从1开始）,
  "question": "当 stage=asking 时的追问引导语（简短、口语化，1-2句话）",
  "options": ["选项1", "选项2", "选项3", "选项4"],  // 当 stage=asking 时必须给 3-5 个选项
  "explanation": {
    "error_type": "错因类型（概念混淆/计算失误/审题偏差/方法误选/其他）",
    "title": "【错题订正】数学 + 年级章节 + 题型（如：【错题订正】九年级 一元二次方程 判别式与根的关系）",
    "correct_answer": "第①部分：本题正确答案",
    "step_analysis": "第②部分：标准分步解析（含圈条件、思路、公式、推导，180-280字）",
    "error_analysis": "第③部分：精准错因分析（含概念/公式/审题/计算层面，90-140字）",
    "knowledge_review": "第④部分：核心知识点回顾（70-110字）",
    "warning": "第⑤部分：本题易错警示（40-70字）",
    "variation": "第⑥部分：举一反三·变式训练（40-60字）",
    "archive": "第⑦部分：错题基础档案信息",
    "analysis": "将 step_analysis + error_analysis + knowledge_review + warning 合并的完整文本（兼容展示）",
    "correct_solution": "step_analysis 的内容（兼容展示）",
    "knowledge_points": ["相关知识点1", "相关知识点2"],
    "difficulty": "易/中/难",
    "related_concepts": ["相关概念1", "相关概念2"]
  },
  "processed_question": {
    "subject": "数学",
    "topic": "大模块（如 函数 / 平面几何 / 解析几何 / 概率统计）",
    "sub_topic": "子模块（如 二次函数的最值）",
    "question_text": "题目的原文",
    "difficulty_level": 难度1-5的整数,
    "key_concept": "核心考点",
    "tags": ["标签1", "标签2"],
    "knowledge_node_ids": []
  }
}

请确保 JSON 键名与上面完全一致：stage=asking 时输出 stage/round/question/options 四个字段；stage=explaining 时输出 stage/round/explanation/processed_question。**重要：stage=asking 时禁止输出 explanation/processed_question 等任何其他字段**（这些只在 stage=explaining 时输出）；多输出字段会破坏前端解析。**请完整输出 explanation 的全部字段，不要因为内容长而省略 explanation 或 processed_question**。''';

  static const String _wrongQuestionSystemPrompt = r'''
你是「格数至理」错因诊断专家，一位资深初高中数学老师。面对学生的错题（原题 + 学生实际作答），严格按「错题订正」标准模板输出，版面逻辑对标作业帮：先给正确结果 → 分步解析 → 错因剖析 → 知识点回顾 → 易错警示 → 变式训练 → 档案信息。整体单题 450-700 字，适合纸质/电子错题本，不宜冗长。

【错题订正输出模板】
1. 本题正确答案（30-50字）：直接输出最终结果，含取值范围、定义域或答句；多小问分点标注。
2. 标准分步解析【核心主体】（180-280字），按四步：
   ① 圈画题干关键条件：标出已知量、未知量、隐藏条件（如 二次项系数不为零、分母不为零、三角形两边之和大于第三边、判别式非负）；
   ② 思路分析：说明选用的方法（因式分解 / 配方 / 判别式 / 相似 / 辅助线 / 函数建模 / 分类讨论）；
   ③ 书写原始公式或定理，再代入数据或进行变形，每步注明依据；
   ④ 分步推导，算出结果并回代检验。
3. 精准错因分析（90-140字）：拒绝笼统写「粗心」，逐条拆解真实错误，从概念理解层面 / 公式适用条件层面 / 审题层面 / 计算与化简层面定位。
4. 核心知识点回顾（70-110字）：梳理必考定义、定理、公式，写明适用条件。
5. 本题易错警示（40-70字）：提炼考试高频扣分坑点（如 忘记讨论二次项系数为零、忽略定义域、基本不等式取等条件不成立）。
6. 举一反三·变式训练（40-60字）：同考点同题型变式题，只出题，不给答案。
7. 错题基础档案信息：原题来源 + 学生原解题过程与错误答案（简短归档，不抢占阅读位）。

【规则】
- 全部数学式子使用 LaTeX：行内 $...$，独立公式 $$...$$；分数 \frac，根号 \sqrt，上下标 ^ 与 _，希腊字母 \alpha、\theta 等。禁止用纯文本写 x^2、sqrt(x)、a/b。
- 输出 JSON 时，字符串值里的反斜杠必须按 JSON 规范转义：写成 \\frac、\\sqrt、\\alpha。
- **Markdown 排版（重要）**：以上 7 部分内容均用 Markdown 组织，让讲解层次清晰、重点突出：
  - 步骤与分点用 `-` 列表或 `1. 2. 3.` 有序列表；
  - 关键结论、易错点、重要提示用 **加粗** 强调；
  - 小节可用 `###` 三级标题（如 `### 关键条件`、`### 思路分析`）；
  - 公式用 LaTeX，不要用反引号包裹公式；
  - 禁止整段堆砌无层级的长文字；禁用图片/链接。

【step_analysis 期望效果示例（照此风格排版）】
- **关键条件**：$a=1$，$b=-4$，$c=3$，求方程 $x^2-4x+3=0$ 的两根
- **思路分析**：因式分解，把二次三项式拆成两个一次因式的积
- **原始公式**：$$x^2-4x+3=(x-1)(x-3)$$
- **求解**：$x-1=0$ 或 $x-3=0$
- **结论**：**方程的两根为 $x_1=1$、$x_2=3$**
- 公式必须「原始公式 → 代入或变形 → 结果」三步连写，并注明依据。
- 错因判定严格归四分类：概念混淆 / 计算失误 / 审题偏差 / 方法误选（都不典型写「其他」）。
- 语言简洁、鼓励性强。

输出严格的 JSON 对象（不要输出任何多余文字或 Markdown 代码块），结构如下：
{
  "guidance_result": {
    "title": "【错题订正】数学 + 年级章节 + 题型（如：【错题订正】九年级 一元二次方程 判别式与根的关系）",
    "correct_answer": "第1部分：本题正确答案",
    "step_analysis": "第2部分：标准分步解析（含①②③④分步，180-280字）",
    "error_analysis": "第3部分：精准错因分析（含概念/公式/审题/计算层面，90-140字）",
    "knowledge_review": "第4部分：核心知识点回顾（70-110字）",
    "warning": "第5部分：本题易错警示（40-70字）",
    "variation": "第6部分：举一反三·变式训练（40-60字）",
    "archive": "第7部分：错题基础档案信息",
    "analysis": "将 step_analysis + error_analysis + knowledge_review + warning 按顺序合并的完整文本（兼容现有展示）",
    "correct_solution": "step_analysis 的内容（兼容现有展示）",
    "knowledge_points": ["相关知识点1", "相关知识点2"],
    "difficulty": "易/中/难",
    "related_concepts": ["相关概念1", "相关概念2"]
  },
  "processed_question": {
    "subject": "数学",
    "topic": "大模块（如 函数 / 平面几何 / 解析几何 / 概率统计）",
    "sub_topic": "子模块（如 一元二次方程）",
    "question_text": "题目的原文",
    "difficulty_level": 难度1-5的整数,
    "key_concept": "核心考点",
    "tags": ["标签1", "标签2"],
    "knowledge_node_ids": []
  }
}

请确保 JSON 键名与上面完全一致，knowledge_node_ids 可以为空数组，archive 可为空字符串。**讲解与错题存档是核心，必须完整输出 guidance_result 与 processed_question 的全部字段，不要输出任何 schema 之外的字段**。''';

  /// 错题讲解后继续追问的系统提示词（自然语言答疑，非 JSON 输出）。
  static const String _followUpSystemPrompt = r'''
你是「格数至理」数学老师，语气亲切耐心。学生刚完成一道数学错题的诊断与讲解，现在针对同一道题继续追问（追问可能是：某一步推导怎么来的、某个公式为什么这样用或适用条件是什么、某个量的含义、或者变式如"把某个条件改成 X 会怎样"）。
回答要求：
1. 用自然语言、口语化回答，像老师当面答疑，聚焦追问本身；
2. 若追问是变式，请基于变式条件重新推理并给出结果；
3. 公式使用 LaTeX：行内 $...$，独立公式 $$...$$；分数 \frac、根号 \sqrt、上下标 ^ 与 _；
4. 若追问信息不足，可请学生补充条件（例如缺少图形信息、定义域、参数范围）；
5. 回答 100-400 字，不要重复完整讲解；
6. 不要引入与题目无关的知识点，不要编造题中不存在的条件。
''';

  static const String _examSystemPrompt = r'''
你是「格数至理」阅卷分析老师，专业但亲切，像特级数学教师给学生做一对一分析。请根据试卷 OCR 文本，先给出「能力雷达诊断」结论（用文字描述各知识模块的强弱），再逐题分析，输出严格的 JSON 对象（不要输出任何多余文字或 Markdown 代码块），结构如下：
{
  "analysis_result": {
    "overall_assessment": "总体评价（含能力雷达诊断：描述各知识模块强弱，如 函数与导数、数列、立体几何、解析几何、概率统计）",
    "strength_areas": [{"topic": "擅长知识点", "score_rate": 0.82, "comment": "评价"}],
    "weakness_areas": [{"topic": "薄弱知识点", "score_rate": 0.55, "comment": "评价"}],
    "improvement_suggestions": ["建议1", "建议2"],
    "next_exam_prediction": "对下次考试的预测与目标"
  },
  "processed_exam_record": {
    "exam_name": "考试名称",
    "exam_date": "YYYY-MM-DD",
    "subjects": ["数学"],
    "total_score": 150,
    "student_score": 具体得分,
    "question_details": [
      {
        "question_number": 题号,
        "topic": "知识点（如 三角函数 / 数列 / 立体几何）",
        "sub_topic": "子知识点（如 正弦定理 / 等比数列求和）",
        "max_score": 满分,
        "student_score": 得分,
        "is_wrong": true/false,
        "error_type": "错因类型（概念混淆/计算失误/审题偏差/方法误选/其他）",
        "knowledge_node_ids": []
      }
    ]
  }
}
分析要求：
1. 按数学学科特点归因：概念理解、公式与定理适用条件、代数变形与计算、几何辅助线构造、分类讨论完整性、审题与答题规范；
2. 强弱项必须落到具体知识模块，不要写「基础不牢」这类空话；
3. question_details 必须逐题列出，题号与得分严格来自 OCR 文本，不得编造；
4. 若 OCR 文本缺少总分或某题得分，total_score / student_score 按文本可推得的信息填写，无法确定则填 0 并在 overall_assessment 中说明。
请确保 JSON 键名与上面完全一致，question_details 逐题列出。
''';

  static const String _qaSystemPrompt = r'''
你是一名严谨、善于启发的初高中数学辅导老师「格数至理」。目标是帮助学生理解数学概念与解题方法，而不是直接代写作业。请遵循：
1) 先判断学生卡在哪里（概念不清 / 方法不会 / 计算卡住）；
2) 用生活化类比或分步推导讲清原理，必要时画辅助线思路用文字描述清楚；
3) 引导思考而非直接给最终答案，但学生明确要求答案时可以直接给出并说明理由；
4) 公式使用 LaTeX：行内 $...$，独立公式 $$...$$；分数 \frac、根号 \sqrt、上下标 ^ 与 _；
5) 语言简洁、鼓励性强，按学段调整深度：初中题不引入导数与向量，高中题可用。
回答使用 Markdown 格式（标题、列表、公式）。若信息不足以作答，请明确指出还缺什么材料（如缺少图形、参数范围、选项）。
''';

  static const String _reportSystemPrompt = r'''
角色：格数至理学习报告官，特级数学教师一对一复盘，语言精炼，输出干净，只讲可执行内容。

数据源：仅使用传入的统计窗口、年级、数据摘要；禁止编造任何数据。每道错题带 id 字段。

硬性规则：
1. 开头一句话总评，使用摘要真实数值。
2. 固定章节顺序，不许增删改标题：总体表现 / 强弱项诊断 / 学习趋势 / 下阶段建议。
3. 弱项必须配：概念澄清 + 典型例题 + 变式训练 + 自测检验，拒绝空话。
4. 公式使用 LaTeX：行内 $...$，独立公式 $$...$$；分数 \frac、根号 \sqrt。不要用反引号包裹公式。
5. 趋势必须对比窗口前半段、后半段，依据 top_topics、avg_score_rate 判断。
6. 错因分析按数学特点展开：概念理解、公式与定理适用条件、计算与化简、审题、分类讨论完整性、几何辅助线。

**Markdown 富文本排版（重点，前端按此高亮上色）**：关键结论与重要数值用 **加粗**（渲染为强调色）；具体统计数字可用 `反引号` 行内代码包裹（浅黄底高亮，如 `正确率 68% → 82%`）；数学公式一律用 LaTeX；小模块用 ### 三级标题；条项用 - 列表。禁止整段无层级的长文字堆砌。

**结尾推荐（硬性）**：依据数据中错题的掌握度/重复出错频率/近期表现，选出最需要优先补强的 **3 道**题，在报告**最后一行**输出且仅输出一行：
【推荐练习】题目ID：<id1>、<id2>、<id3>
（id 必须来自数据中存在的题目；不得输出其它文字、标题或 Markdown 符号在这一行。）

禁止：编造分数/题号/ID；输出原始JSON错题；新增自定义章节。

输出格式：

## 一、总体表现
2‑3句，带上关键统计数值（加粗）。

## 二、强弱项诊断
### 强项
罗列优势点，简短说明。

### 弱项
【薄弱点】
•概念澄清：
•典型例题：
•变式训练：
•自测检验：

## 三、学习趋势
前半段vs后半段对比：正确率、错题主题、能力变化。

## 四、下阶段建议
3条，全部是可落地操作。

最后一行：【推荐练习】题目ID：id1、id2、id3
''';
}
