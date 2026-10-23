import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/widgets/error_display_widget.dart';
import '../../../shared/utils/base64_util.dart';
import '../../../shared/widgets/styled_markdown.dart';
import '../../../core/network/network_provider.dart';
import '../../../core/network/sse_parser.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/repositories/wrong_question_repository.dart';
import '../../../data/datasources/remote/dify_response_models.dart';
import '../providers/wrong_question_providers.dart';
import '../../home/providers/student_insight_provider.dart';
import '../services/student_stats_builder.dart';

class WrongQuestionChatPage extends ConsumerStatefulWidget {
  const WrongQuestionChatPage({super.key});
  @override
  ConsumerState<WrongQuestionChatPage> createState() =>
      _WrongQuestionChatPageState();
}

class _WrongQuestionChatPageState extends ConsumerState<WrongQuestionChatPage> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  XFile? _pickedImage;
  bool _loading = false;
  bool _expertMode = false; // false=快速版(一问一答)，true=专家版(多轮循环对话)
  String? _analysis, _solution, _error;
  List<String> _knowledgePoints = [];
  String _difficulty = '';
  GuidanceResult? _guidanceResult; // 完整解析结果（含错题订正 7 段字段）
  String _originalQuestion = ''; // 原题文本（AI 提取，用于折叠展示）
  String? _questionImageBase64; // 快速版发送的原题图片（展开原题时一并展示）
  final List<(String, String)> _quickFollowUps = []; // 快速版讲解后追问记录 (追问, 回答)
  String? _streamText; // 快速版流式输出：AI 原始流（生成中展示，完成后收起）
  final StringBuffer _streamBuf = StringBuffer(); // 流式累加缓冲
  final _streamScroll = ScrollController();
  String _waitPhase = '正在提交…'; // 流式前的等待阶段提示（压缩/OCR/生成）
  int _submitStartMs = 0; // 本次提交起点（供首Token计时）
  int? _ttfbMs; // 首Token耗时（TTFB，毫秒）

  // ── 专家版（多轮循环对话）状态 ──────────────────────────
  bool _expertLoading = false;
  int _expertRound = 0; // 已追问轮数（决策树最深约4层）
  bool _expertDone = false; // 讲解完成
  _ExpertNode _treeNode = _ExpertNode.root; // 当前决策树节点（前端驱动）
  int _expertRetryCount = 0; // JSON 解析失败自动重试计数
  String? _expertError;
  final List<Map<String, String>> _expertTurns =
      []; // 追问-回答对话记录 {role: user|assistant, text}
  final List<_ExpertBubble> _expertBubbles = []; // 展示用对话气泡
  Map<String, dynamic>? _expertResult; // 讲解结果 JSON
  int _expertResultBubbleCount = 0; // 讲解结果卡在气泡列表中的插入位置（后续追问气泡排在卡之后）
  String? _expertImageBase64; // 首轮图片（保存时复用）
  bool _expertAiUseImage = true; // 专家版是否把图片喂给 AI（OCR 后 false，AI 走纯文本）
  String? _expertQuestionText; // 首轮题目文本（保存时复用）
  final _expertScroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _expertScroll.dispose();
    _streamScroll.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await _picker.pickImage(source: source, imageQuality: 80);
    if (image != null) {
      setState(() => _pickedImage = image);
    }
  }

  Future<String?> _compressToBase64(XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      const maxW = 1200.0;
      double w = decoded.width.toDouble();
      double h = decoded.height.toDouble();
      if (w > maxW) {
        h = h * maxW / w;
        w = maxW;
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        decoded,
        Rect.fromLTWH(
          0,
          0,
          decoded.width.toDouble(),
          decoded.height.toDouble(),
        ),
        Rect.fromLTWH(0, 0, w, h),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final img = await recorder.endRecording().toImage(w.round(), h.round());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return 'data:image/png;base64,${base64Encode(byteData.buffer.asUint8List())}';
    } catch (e) {
      debugPrint('[IMG] 压缩失败: $e');
      return null;
    }
  }

  /// OCR 请求加 8 秒超时：识别太慢就放弃（改为图片直发），不让首Token等太久。
  Future<String?> _safeOcr(String imageBase64) async {
    try {
      return await ref
          .read(aliyunApiClientProvider)
          .ocrQuestionImage(imageBase64)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      debugPrint('[Stream] OCR 超时/失败，改为图片直发');
      return null;
    }
  }

  /// OCR 质量门控：返回 (是否采用OCR, 题目文本, 是否保留图片)。
  ///
  /// - 电子/印刷题：OCR 可信 → 采用纯文本（判型更稳），不喂图；
  /// - 手写拍照题：OCR 可能输出错乱文本 → 质量不足时**保留图片直发**，
  ///   让多模态模型直接看手写图（比错误文本可靠）；
  /// - 含图形/曲线（函数图象、几何图形、统计图等 OCR 无法表达）→ 文本+图片
  ///   双通道一起喂，多模态模型可自行读图补全图形信息。
  (bool, String, bool) _ocrGate(String ocr, String placeholderText) {
    final t = ocr.trim();
    if (t.isEmpty) return (false, placeholderText, true);
    // 质量门槛：过短 / 无中文 / 无数值与单位 → 判定手写识别失败，走图片
    final cjkCount = RegExp(r'[\u4e00-\u9fff]').allMatches(t).length;
    final hasQuantity = RegExp(
      r'[0-9０-９]|cm|km|米|厘米|分米|度|°|元|个|次|项|倍',
    ).hasMatch(t);
    if (t.length < 10 || cjkCount < 2 || !hasQuantity) {
      return (false, placeholderText, true);
    }
    // 含图形/曲线：OCR 转写不出图 → 文字+图片双通道
    final hasFigure = RegExp(r'如图|图像|图象|图甲|图乙|图丙|曲线|图形|示意图|函数图|几何图').hasMatch(t);
    return (true, t, hasFigure);
  }

  Future<void> _submit() async {
    var text = _controller.text.trim();
    if (text.isEmpty && _pickedImage == null) return;
    if (text.isEmpty && _pickedImage != null) {
      text = '请分析这道题';
    }
    setState(() {
      _loading = true;
      _error = null;
      _analysis = null;
      _solution = null;
      _knowledgePoints = [];
      _quickFollowUps.clear();
      _streamBuf.clear();
      _streamText = null;
      _submitStartMs = DateTime.now().millisecondsSinceEpoch;
      _ttfbMs = null;
      _waitPhase = '正在提交…';
    });

    try {
      // 压缩图片为 base64，同时用于错题本存储和阿里云多模态识别
      String? imageBase64;
      if (_pickedImage != null) {
        if (mounted) setState(() => _waitPhase = '压缩图片中…');
        imageBase64 = await _compressToBase64(_pickedImage!);
        _questionImageBase64 = imageBase64; // 供展开原题时展示发送图片
      }
      // 识图：快速模式为追求速度，跳过 OCR 预识别（省一整轮 LLM 调用），
      // 直接把图片喂给多模态模型读图生成；文字仅作占位/补充
      var aiSeeImage = imageBase64 != null;
      if (imageBase64 != null) {
        if (mounted) setState(() => _waitPhase = 'AI 生成中…');
      }

      final repo = ref.read(wrongQuestionRepositoryProvider);
      // 快速版个性化：打包学生错题统计 + 学习画像（不发具体题目，只发数量/分布）
      final studentStats = await _buildStudentStatsWithInsight();
      await for (final step in repo.submitQuestion(
        questionText: text,
        imageBase64: imageBase64,
        studentStatsJson: studentStats,
        aiSeeImage: aiSeeImage,
      )) {
        switch (step) {
          case ChunkGuidanceStep(:final text):
            // 流式输出：实时追加 AI 原始文本（生成中展示，完成后收起）
            _streamBuf.write(text);
            // 首Token计时（TTFB）：直接回答"第一个 token 花了多久"
            if (_ttfbMs == null) {
              _ttfbMs = DateTime.now().millisecondsSinceEpoch - _submitStartMs;
              debugPrint('[Stream] 首Token TTFB: ${_ttfbMs}ms');
            }
            if (mounted) {
              setState(() => _streamText = _streamBuf.toString());
              // 强制等待一帧渲染完成再处理下一个增量：
              // 防止连续 setState 被 Flutter 合并成一次重绘（表现为"没有流式"）
              await WidgetsBinding.instance.endOfFrame;
              if (_streamScroll.hasClients) {
                _streamScroll.jumpTo(_streamScroll.position.maxScrollExtent);
              }
            }
          case ResultGuidanceStep(
            :final result,
            :final questionText,
          ):
            setState(() {
              _guidanceResult = result;
              _originalQuestion = questionText.isNotEmpty
                  ? questionText
                  : _originalQuestion;
              _analysis = result.analysis;
              _solution = result.correctSolution;
              _knowledgePoints = result.knowledgePoints;
              _difficulty = result.difficulty;
              _streamText = null; // 流式原文收起，换成结构化卡片
            });
            // 记录本次讲解的具体错误点到学习画像（快速版：以知识点+错因分析为指纹信号）
            try {
              ref
                  .read(studentInsightProvider.notifier)
                  .recordSession(
                    source: 'quick',
                    questionText: _originalQuestion.isNotEmpty
                        ? _originalQuestion
                        : text,
                    explanation: {
                      'error_analysis': result.errorAnalysis,
                      'title': result.title,
                    },
                    processedQuestion: {
                      'sub_topic': result.knowledgePoints.join(';'),
                    },
                  );
            } catch (_) {}
          case ErrorGuidanceStep(:final message):
            setState(() {
              _error = message;
              _streamText = null;
            });
          default:
            break;
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }

    if (mounted && _analysis != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已自动保存至错题本'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => context.go('/wrong-question/list'),
          ),
        ),
      );
    }
  }

  // ── 快速版：讲解完成后继续追问 ──────────────────────────
  Future<void> _quickFollowUp() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      final contextText =
          '【题目】$_originalQuestion\n\n'
          '【已完成讲解】\n题目分析：$_analysis\n正确解法：$_solution';
      final buffer = StringBuffer();
      await for (final event
          in ref
              .read(aliyunApiClientProvider)
              .followUpWrongQuestion(
                messages: [
                  {'role': 'user', 'content': contextText},
                  {'role': 'user', 'content': '学生追问：$text'},
                ],
              )) {
        switch (event) {
          case MessageChunk(:final answer):
            buffer.write(answer);
          case StreamError(:final message):
            throw Exception(message);
          default:
            break;
        }
      }
      final answer = buffer.toString().trim();
      setState(() {
        _controller.clear();
        _quickFollowUps.add((text, answer));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('追问失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── 快速版：讲解完成后回位（重置为可重新提问的初始状态） ──
  void _resetQuick() {
    setState(() {
      _loading = false;
      _error = null;
      _analysis = null;
      _solution = null;
      _knowledgePoints = [];
      _difficulty = '';
      _guidanceResult = null;
      _originalQuestion = '';
      _quickFollowUps.clear();
      _controller.clear();
      _pickedImage = null;
      _questionImageBase64 = null;
    });
  }

  // ── 专家版：发起第一轮（提交题目/图片 + 学生画像） ──────
  Future<void> _startExpert() async {
    var text = _controller.text.trim();
    if (text.isEmpty && _pickedImage == null) return;
    if (text.isEmpty) text = '请分析这道题';
    if (_expertLoading) return;

    String? imageBase64;
    if (_pickedImage != null) {
      imageBase64 = await _compressToBase64(_pickedImage!);
    }

    // 识图优化（专家版保留 OCR 判型更稳）：有图且仅占位文字时，先用多模态识别题目文本
    var aiUseImage = true;
    if (imageBase64 != null && (text == '请分析这道题' || text.isEmpty)) {
      final ocr = await _safeOcr(imageBase64);
      final gate = _ocrGate(ocr ?? '', text);
      if (gate.$1) {
        text = gate.$2;
        aiUseImage = gate.$3; // 手写/含图题保留图片，多模态模型自己看图
      }
    }

    // 学生错题画像（仅统计，用于个性化追问与讲解）
    final stats = await _buildStudentStatsWithInsight();

    // 首轮题目文本（含画像，注入 _buildExpertScript 的【题目】段）
    final questionText = (stats != null && stats.isNotEmpty)
        ? '$text\n\n【学生错题画像（仅统计信息，用于个性化追问与讲解）】\n$stats'
        : text;

    setState(() {
      _expertTurns.clear();
      _expertBubbles.clear();
      _expertBubbles.add(_ExpertBubble(isUser: true, content: text));
      _expertRound = 0;
      _expertDone = false;
      _expertRetryCount = 0;
      _treeNode = _ExpertNode.root;
      _expertResult = null;
      _expertResultBubbleCount = 0;
      _expertError = null;
      _expertQuestionText = questionText;
      _expertImageBase64 = imageBase64;
      _expertAiUseImage = aiUseImage;
      _controller.clear();
      _pickedImage = null;
    });
    await _runExpertTurn();
  }

  // ── 专家版：用户回答追问（可从选项按钮或输入框触发） ─────
  Future<void> _replyExpert([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _expertLoading || _expertDone) return;
    setState(() {
      _expertTurns.add({'role': 'user', 'text': text});
      _expertBubbles.add(_ExpertBubble(isUser: true, content: text));
      _treeNode = _advanceExpertNode(_treeNode, text); // 根据学生回答沿树推进
      _controller.clear();
    });
    await _runExpertTurn();
  }

  /// 局部提取 asking 轮字段：JSON 即使被截断，也能从文本抠出 question 与 options，
  /// 保证选项按钮正常渲染。返回值：null=非 asking 或无法提取；(问题, 选项列表)。
  (String, List<String>)? _tryExtractAsking(String raw) {
    if (!raw.contains('"asking"')) return null;
    final qm = RegExp(r'"question"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(raw);
    if (qm == null) return null;
    String clean(String g) =>
        g.replaceAll(r'\"', '"').replaceAll(r'\\\\', r'\\');
    final question = clean(qm.group(1)!);
    final om = RegExp(r'"options"\s*:\s*\[([\s\S]*?)\]').firstMatch(raw);
    if (om == null) return (question, const []);
    final opts = RegExp(r'"((?:[^"\\]|\\.)*)"')
        .allMatches(om.group(1)!)
        .map((m) => clean(m.group(1)!))
        .where((s) => s.isNotEmpty)
        .toList();
    return (question, opts);
  }

  /// 从可能含前缀/后缀/截断的文本中提取第一个完整 JSON 对象。
  Map<String, dynamic>? _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    for (var i = start; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          final sub = raw.substring(start, i + 1);
          try {
            final d = json.decode(sub);
            if (d is Map<String, dynamic>) return d;
          } catch (_) {}
          return null;
        }
      }
    }
    return null;
  }

  /// 决策树节点推进

  _ExpertNode _advanceExpertNode(_ExpertNode n, String answer) {
    switch (n) {
      case _ExpertNode.root:
        if (answer.contains('没有分析出状态')) return _ExpertNode.aSimilar;
        if (answer.contains('没有进行计算')) return _ExpertNode.bWhy;
        if (answer.contains('算出了一些量')) return _ExpertNode.cQuantity;
        if (answer.contains('算完') || answer.contains('算错')) {
          return _ExpertNode.dWhich;
        }
        return _ExpertNode.cQuantity; // 不匹配时保守推进到 C 分支
      case _ExpertNode.aSimilar:
        if (answer.contains('没见过')) return _ExpertNode.aLeafDiff;
        if (answer.contains('不知道怎么写')) return _ExpertNode.aLeafBasic;
        return _ExpertNode.aLeafGeneral; // 其余归通法叶子
      case _ExpertNode.bWhy:
        if (answer.contains('不记得公式')) return _ExpertNode.bLeafFormula;
        if (answer.contains('不知道怎么开始')) return _ExpertNode.bLeafStart;
        return _ExpertNode.bLeafUse;
      case _ExpertNode.cQuantity:
        return _ExpertNode.cWhy; // 选了某个量，进入下一层
      case _ExpertNode.cWhy:
        if (answer.contains('数字')) return _ExpertNode.cLeafNum;
        if (answer.contains('运动')) return _ExpertNode.cLeafMotion;
        if (answer.contains('列式子')) return _ExpertNode.cLeafEqn;
        return _ExpertNode.cLeafEq;
      case _ExpertNode.dWhich:
        return _ExpertNode.dLeaf;
      default:
        return n; // 已在叶子，不再推进
    }
  }

  bool _isLeafNode(_ExpertNode n) => switch (n) {
    _ExpertNode.aLeafDiff ||
    _ExpertNode.aLeafGeneral ||
    _ExpertNode.aLeafBasic ||
    _ExpertNode.bLeafFormula ||
    _ExpertNode.bLeafUse ||
    _ExpertNode.bLeafStart ||
    _ExpertNode.cLeafNum ||
    _ExpertNode.cLeafEq ||
    _ExpertNode.cLeafMotion ||
    _ExpertNode.cLeafEqn ||
    _ExpertNode.dLeaf => true,
    _ => false,
  };

  /// 当前节点指令：前端明确指定本轮要问的问题层级与选项（AI 润色措辞但选项原样保留），
  /// 叶子节点则直接给出讲解重点。
  String _nodeInstruction(_ExpertNode n) {
    const fixedOpts = '（选项必须原样保留，不得增删改）';
    switch (n) {
      case _ExpertNode.root:
        return '【本轮任务：决策树第1层根问题】提出根问题："这道题你当时处理到了哪一步？"，选项为：没有分析出状态 / 分析好了，但没有进行计算 / 已经算出了一些量，但没有算完 / 算完了，但是算错了 $fixedOpts';
      case _ExpertNode.aSimilar:
        return '【本轮任务：决策树第2层】提出问题："类似的题目你平时会写吗？"，选项为：会写，只是这道题没见过 / 这类题目平时都不太会 / 完全不知道怎么写 $fixedOpts';
      case _ExpertNode.bWhy:
        return '【本轮任务：决策树第2层】提出问题："为什么没有进行计算？"，选项为：不记得公式了 / 不知道怎么用公式 / 不知道怎么开始 $fixedOpts';
      case _ExpertNode.cQuantity:
        return '【本轮任务：决策树第2层·结合本题】提出问题："你算出了哪些量？"。请先自行推导/计算出本题各关键量的**正确数值**，再给出 3-5 个选项；**每个选项的数字必须是正确值**（供学生核对自己算的结果），写明「哪个物体的什么量 = 正确数值+单位」（如「物体A的末速度 v=6 m/s」「物体A的加速度 a=2 m/s²」），表述严谨；只列需要计算的中间量，不罗列题目已知条件';
      case _ExpertNode.cWhy:
        return '【本轮任务：决策树第3层】提出问题："那为什么后面算不出来了？"，选项为：数字太复杂，不像对的 / 方程解不出来 / 不知道后面怎么运动 / 不知道后面怎么列式子 $fixedOpts';
      case _ExpertNode.dWhich:
        return '【本轮任务：决策树第2层·结合本题】提出问题："检查一下是哪一个数据算错了？"。请**先自行推导/计算**本题各关键量的正确数值，再给出 3-5 个选项，**每个选项写明「哪个物体的什么量 = 可能算错的具体数值+单位」**（把各关键量按你推导出的数值填入，如「物体的加速度 a = 3 m/s²」「物体的位移 s = 6 m」），表述严谨；只列关键中间量与结果量';
      case _ExpertNode.aLeafDiff:
        return '【到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问】学生"会写，只是这道题没见过"。讲解重点：额外分析此题与其他题目的差异之处，重点放在状态分析上；建议多刷此类题。';
      case _ExpertNode.aLeafGeneral:
        return '【到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问】学生"这类题目平时都不太会"。讲解重点：此类题目的一般状态与通法。';
      case _ExpertNode.aLeafBasic:
        return '【到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问】学生"完全不知道怎么写"。讲解重点：先直接讲解相关基础知识，再结合题目讲解。';
      case _ExpertNode.bLeafFormula:
        return '【到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问】学生"不记得公式了"。讲解重点：先列出相关公式，重点放在原始公式的讲解与理解上（可用口诀或结合实际事例促进理解记忆）。';
      case _ExpertNode.bLeafUse:
        return '【到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问】学生"不知道怎么用公式"。讲解重点：先列出相关公式，重点放在公式的理解（各项含义、适用条件），结合题目讲解如何应用。';
      case _ExpertNode.bLeafStart:
        return '【到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问】学生"不知道怎么开始"。讲解重点：重点讲如何切入题目、如何判断切入点。';
      case _ExpertNode.cLeafNum:
        return '【到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问】学生"数字太复杂，不像对的"。讲解重点：正常讲解，末尾提示"如果检查出不对的数据，不知道为什么还可以继续追问"。';
      case _ExpertNode.cLeafEq:
        return '【到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问】学生"方程解不出来"。讲解重点：正常讲解，重点标注算不出来的方程。';
      case _ExpertNode.cLeafMotion:
        return '【到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问】学生"不知道接下来该怎么算"。讲解重点：讲清前面得到的结论如何对应下一步的式子变形与代入。';
      case _ExpertNode.cLeafEqn:
        return '【到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问】学生"不知道后面怎么列式子"。讲解重点：重点讲后面的运动状态如何对应具体方程。';
      case _ExpertNode.dLeaf:
        return '【到达叶子节点，立即输出 stage=explaining 讲解，禁止再提问】学生指出了算错的关键量。讲解重点：分析时可以标注"如果某处出现某常见错误，会导致什么样的错误计算结果"。';
    }
  }

  /// 把完整对话历史折叠成一条脚本文本（qwen-plus 兼容模式不读取 assistant 角色历史）。
  String _buildExpertScript() {
    final b = StringBuffer('【题目】${_expertQuestionText ?? ''}');
    for (final t in _expertTurns) {
      final who = t['role'] == 'assistant' ? '专家' : '学生';
      b.write('\n$who：${t['text']}');
    }
    // 前端驱动的决策树节点指令：本轮明确指定问题层级/选项，或叶子讲解重点
    b.write('\n${_nodeInstruction(_treeNode)}');
    // 已追问 ≥3 轮时兜底强制进入讲解（防止模型仍输出提问）
    if (_expertRound >= 3 && !_isLeafNode(_treeNode)) {
      b.write('\n【额外硬性要求：本轮禁止再提问，直接输出 stage=explaining 讲解。】');
    }
    return b.toString();
  }

  // ── 专家版：一轮 AI 调用（追问 or 讲解） ────────────────
  Future<void> _runExpertTurn({bool isRetry = false}) async {
    setState(() => _expertLoading = true);
    try {
      final client = ref.read(aliyunApiClientProvider);
      // 本轮消息：完整对话脚本（含图时附带图片，保证每轮都能看到题图）
      final script = _buildExpertScript();
      final List<Map<String, dynamic>> messages;
      final img = _expertAiUseImage ? _expertImageBase64 : null;
      if (img != null && img.isNotEmpty) {
        messages = [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': script},
              {
                'type': 'image_url',
                'image_url': {'url': img},
              },
            ],
          },
        ];
      } else {
        messages = [
          {'role': 'user', 'content': script},
        ];
      }
      final buffer = StringBuffer();
      await for (final event in client.submitExpertRound(messages: messages)) {
        switch (event) {
          case MessageChunk(:final answer):
            buffer.write(answer);
          case StreamError(:final message):
            throw Exception(message);
          default:
            break;
        }
      }
      final raw = buffer.toString().trim();
      Map<String, dynamic>? parsed;
      try {
        final decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) parsed = decoded;
      } catch (_) {
        // 截断/多余前缀时尝试从文本中提取 JSON 对象
        parsed = _extractJsonObject(raw);
      }

      if (parsed == null) {
        // 局部提取：asking 轮即使 JSON 被截断，也先用正则抠出 question/options 正常渲染（选项按钮不能丢）
        final asking = _tryExtractAsking(raw);
        if (asking != null) {
          setState(() {
            _expertRound++;
            _expertBubbles.add(
              _ExpertBubble(
                isUser: false,
                content: asking.$1,
                options: asking.$2,
              ),
            );
            _expertTurns.add({'role': 'assistant', 'text': asking.$1});
          });
          _scrollExpert();
          return;
        }
        // 解析失败：自动重试（≤2 次），提示模型重新输出严格 JSON
        if (!isRetry && raw.isNotEmpty && _expertRetryCount < 2) {
          _expertRetryCount++;
          _expertTurns.add({
            'role': 'user',
            'text':
                '（系统提示：你上一条回复不是有效的 JSON。请立即重新输出严格的 JSON 对象：asking 轮仅 {stage,round,question,options}，explaining 轮 {stage,round,explanation,processed_question}。不要输出任何多余文字或 Markdown 代码块。）',
          });
          _runExpertTurn(isRetry: true);
          return;
        }
        // 最终兜底：仍像 JSON 则不贴原始代码（截断/异常），给友好提示；纯文本才展示原文
        final looksJson =
            raw.trimLeft().startsWith('{') || raw.trimLeft().startsWith('[');
        final content = raw.trim().isEmpty
            ? '（AI 未返回有效内容，请点击「再来一道」重试）'
            : (looksJson ? '（AI 返回未完整，请点击「再来一道」重试）' : raw);
        setState(() {
          _expertBubbles.add(_ExpertBubble(isUser: false, content: content));
          _expertDone = true;
          _expertResultBubbleCount = _expertBubbles.length;
        });
        return;
      }

      final stage = parsed['stage'] as String? ?? 'explaining';
      if (stage == 'asking' && _expertRound < 6) {
        // 兼容 question 为 String 或 List（多模态模型可能返回数组）
        final qRaw = parsed['question'];
        String? q;
        if (qRaw is String) {
          q = qRaw.trim();
        } else if (qRaw is List && qRaw.isNotEmpty) {
          q = qRaw.map((e) => e.toString()).join('\n').trim();
        }
        if (q != null && q.isNotEmpty) {
          final question = q;
          final options =
              (parsed['options'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
          setState(() {
            _expertRound++;
            _expertBubbles.add(
              _ExpertBubble(isUser: false, content: question, options: options),
            );
            _expertTurns.add({'role': 'assistant', 'text': question});
          });
          _scrollExpert();
          return;
        }
        // question 为空：降级走讲解
      }

      // explaining（或已达追问上限强制讲解）
      setState(() {
        _expertResult = parsed;
        _expertDone = true;
        _expertResultBubbleCount = _expertBubbles.length;
      });
      final savedId = await _saveExpertResult(parsed);
      // 记录本次讲解的具体错误点 + 学生疑问点 到学习画像（完整可追溯）
      try {
        final doubts = _expertTurns
            .where((t) => t['role'] == 'user')
            .map((t) => t['text'] ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        ref
            .read(studentInsightProvider.notifier)
            .recordSession(
              source: 'expert',
              questionText: _expertQuestionText ?? '',
              explanation: parsed['explanation'] is Map<String, dynamic>
                  ? (parsed['explanation'] as Map<String, dynamic>)
                  : null,
              processedQuestion:
                  parsed['processed_question'] is Map<String, dynamic>
                  ? (parsed['processed_question'] as Map<String, dynamic>)
                  : null,
              studentDoubts: doubts,
            );
      } catch (_) {}
      final saved = savedId != null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saved ? '讲解完成，已自动保存至错题本' : '讲解完成（错题本保存失败）'),
            action: saved
                ? SnackBarAction(
                    label: '查看',
                    onPressed: () => context.go('/wrong-question/list'),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _expertError = e.toString());
    } finally {
      if (mounted) setState(() => _expertLoading = false);
    }
  }

  /// 讲解完成后保存到错题本（复用快速版 guidance_result 结构）。返回新错题 id（失败为 null）。
  Future<int?> _saveExpertResult(Map<String, dynamic> parsed) async {
    try {
      final explanation = parsed['explanation'];
      final pq = parsed['processed_question'];
      if (explanation is Map<String, dynamic> && pq is Map<String, dynamic>) {
        final repo = ref.read(wrongQuestionRepositoryProvider);
        return repo.saveGuidanceResponse(
          {'guidance_result': explanation, 'processed_question': pq},
          originalText: _expertQuestionText ?? '',
          imageBase64: _expertImageBase64,
        );
      }
    } catch (e) {
      debugPrint('[Expert] 保存失败: $e');
    }
    return null;
  }

  /// 构建学生画像上下文（渐进式分层注入）：
  /// 自动统计层 + 高频具体错误点摘要层（Top5）+ 学生手填薄弱点层。
  /// 完整错误点时间线不入 prompt（画像本身完整可追溯，见设置页）。
  Future<String?> _buildStudentStatsWithInsight() async {
    String? stats;
    try {
      final repo = ref.read(wrongQuestionRepositoryProvider);
      final all = await repo.getList(limit: 500, offset: 0);
      stats = StudentStatsBuilder.build(all);
    } catch (_) {}
    // 自动记录学习画像（历史快照，供设置页查看）
    try {
      ref.read(studentInsightProvider.notifier).recordStats(stats);
    } catch (_) {}
    final insight = ref.read(studentInsightProvider);
    return insight.buildPromptInsight(statsJson: stats);
  }

  void _scrollExpert() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_expertScroll.hasClients) {
        _expertScroll.animateTo(
          _expertScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _resetExpert() {
    setState(() {
      _expertTurns.clear();
      _expertBubbles.clear();
      _expertResult = null;
      _expertResultBubbleCount = 0;
      _expertRound = 0;
      _expertDone = false;
      _expertRetryCount = 0;
      _treeNode = _ExpertNode.root;
      _expertError = null;
      _expertImageBase64 = null;
      _expertAiUseImage = true;
      _expertQuestionText = null;
      _pickedImage = null;
      _controller.clear();
    });
  }

  // ── 专家版：讲解完成后继续追问 ──────────────────────────
  Future<void> _expertFollowUp() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _expertLoading || !_expertDone) return;
    setState(() => _expertLoading = true);
    try {
      // 组装上下文脚本：题目 + 诊断对话 + 讲解内容 + 追问
      final b = StringBuffer('【题目】${_expertQuestionText ?? ''}\n\n【完整诊断对话】\n');
      for (final t in _expertTurns) {
        final who = t['role'] == 'assistant' ? '专家' : '学生';
        b.write('$who：${t['text']}\n');
      }
      b.write('\n【讲解内容】\n');
      final exp = _expertResult?['explanation'];
      if (exp is Map<String, dynamic>) {
        b.write('${exp['analysis'] ?? ''}\n${exp['correct_solution'] ?? ''}');
      }
      b.write('\n\n学生继续追问：$text\n\n请直接回答追问。');
      final script = b.toString();

      final buffer = StringBuffer();
      await for (final event
          in ref
              .read(aliyunApiClientProvider)
              .followUpWrongQuestion(
                messages: [
                  {'role': 'user', 'content': script},
                ],
              )) {
        switch (event) {
          case MessageChunk(:final answer):
            buffer.write(answer);
          case StreamError(:final message):
            throw Exception(message);
          default:
            break;
        }
      }
      final answer = buffer.toString().trim();
      setState(() {
        _expertBubbles.add(_ExpertBubble(isUser: true, content: text));
        _expertBubbles.add(
          _ExpertBubble(
            isUser: false,
            content: answer.isEmpty ? '（无响应内容）' : answer,
          ),
        );
        _controller.clear();
      });
      _scrollExpert();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('追问失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _expertLoading = false);
    }
  }

  /// 快速版 / 专家版自绘分段控件。
  ///
  /// 不用 M3 `SegmentedButton`：其在 Web(CanvasKit) 下对中文标签做固有宽度
  /// 度量时会把每个汉字逐字换行并截断。这里用显式内边距 + `softWrap:false`
  /// 直接锁死单行，保证任何宽度与字体下都正常。
  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF0F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeOption(
            label: '快速版',
            icon: Icons.bolt,
            selected: !_expertMode,
            onTap: () => setState(() => _expertMode = false),
          ),
          const SizedBox(width: 3),
          _modeOption(
            label: '专家版',
            icon: Icons.workspace_premium,
            selected: _expertMode,
            onTap: () => setState(() => _expertMode = true),
          ),
        ],
      ),
    );
  }

  Widget _modeOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.primary : AppColors.mutedForeground,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppColors.primary
                    : AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('错题指导'),
        actions: [
          IconButton(
            icon: const Icon(Icons.book),
            tooltip: '错题本',
            onPressed: () => context.go('/wrong-question/list'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 版本切换：快速版 / 专家版（自绘分段控件，见 _buildModeToggle）
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [_buildModeToggle()],
            ),
          ),
          if (_expertMode)
            Expanded(child: _buildExpertPanel())
          else ...[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Builder(
                builder: (context) {
                  final bool followUp = _analysis != null;
                  return Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Focus(
                              onKeyEvent: (node, event) {
                                // Enter = 发送；Shift+Enter = 换行
                                if (event is KeyDownEvent &&
                                    event.logicalKey ==
                                        LogicalKeyboardKey.enter &&
                                    !HardwareKeyboard.instance.isShiftPressed) {
                                  followUp ? _quickFollowUp() : _submit();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: TextField(
                                controller: _controller,
                                maxLines: 4,
                                minLines: 2,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) =>
                                    followUp ? _quickFollowUp() : _submit(),
                                decoration: InputDecoration(
                                  hintText: followUp
                                      ? '就这道题继续追问...'
                                      : '请输入或粘贴题目...',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: _loading
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!followUp) ...[
                                        AppPressScale(
                                          pressedScale: 0.86,
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons
                                                  .add_photo_alternate_outlined,
                                            ),
                                            tooltip: '上传图片',
                                            onPressed: _pickImage,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      if (followUp) ...[
                                        OutlinedButton.icon(
                                          onPressed: _loading
                                              ? null
                                              : _resetQuick,
                                          icon: const Icon(
                                            Icons.check_circle_outline,
                                            size: 18,
                                          ),
                                          label: const Text('完成'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            foregroundColor: AppColors.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      AppPressScale(
                                        pressedScale: 0.86,
                                        child: IconButton.filled(
                                          onPressed: followUp
                                              ? _quickFollowUp
                                              : _submit,
                                          icon: const Icon(Icons.send),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                      if (!followUp && _pickedImage != null) ...[
                        const SizedBox(height: 8),
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                _pickedImage!.path,
                                height: 100,
                                width: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _pickedImage = null),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: AppStateSwitcher(
                alignment: Alignment.topLeft,
                child: _error != null
                    ? ErrorDisplayWidget(message: _error!, onRetry: _submit)
                    : _analysis == null
                    ? _loading
                          ? (_streamText != null
                                ? _buildStreamingView()
                                : _buildWaitingView())
                          : const Center(
                              child: Text(
                                '输入题目或上传图片获取AI指导',
                                style: TextStyle(
                                  color: AppColors.mutedForeground,
                                ),
                              ),
                            )
                    : SelectionArea(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _buildQuickResult(),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(String title, String content) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            StyledMarkdown(data: content),
          ],
        ),
      ),
    );
  }

  /// 快速版流式前的等待视图：显示当前阶段（压缩/OCR/生成），避免空白误导。
  Widget _buildWaitingView() {
    return Center(
      child: AppReveal(
        offset: const Offset(0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: AppMotion.resolve(context, AppMotion.standard),
              switchInCurve: AppMotion.enter,
              switchOutCurve: AppMotion.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                _waitPhase,
                key: ValueKey<String>(_waitPhase),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.mutedForeground,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '首Token前为模型响应时间，流式开始后逐字显示',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.mutedForeground.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 快速版流式输出视图：AI 生成中的**可读文本**实时展示（逐字段渐进）。
  Widget _buildStreamingView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              const Text(
                'AI 生成中…',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              if (_ttfbMs != null) ...[
                const SizedBox(width: 8),
                Text(
                  '首Token ${(_ttfbMs! / 1000).toStringAsFixed(1)}s',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _streamScroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
              ),
              child: StyledMarkdown(data: _streamPreview(), fontSize: 13.5),
            ),
          ),
        ),
      ],
    );
  }

  /// 从流式累积的 JSON 原文中渐进提取可读字段（标题/答案/解析/分析），
  /// 字段随流到达逐个补齐 → 真正的"逐字流出"效果；提取不到时回退原文。
  String _streamPreview() {
    final raw = _streamBuf.toString();
    if (raw.isEmpty) return '';
    String field(String key) {
      final m = RegExp(
        '"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"',
      ).firstMatch(raw);
      if (m == null) return '';
      return m.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\n', '\n');
    }

    final parts = [
      field('title'),
      field('correct_answer'),
      field('step_analysis'),
      field('error_analysis'),
      field('analysis'),
    ].where((e) => e.isNotEmpty).toList();
    final preview = parts.join('\n\n');
    return preview.isNotEmpty ? preview : raw;
  }

  // ── 专家版面板：状态条 + 对话气泡流 + 讲解卡 + 输入区 ──
  Widget _buildExpertPanel() {
    return Column(
      children: [
        _expertStatusBar(),
        Expanded(
          child: _expertBubbles.isEmpty
              ? _expertEmptyState()
              : SelectionArea(
                  child: ListView.builder(
                    controller: _expertScroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount:
                        _expertBubbles.length + (_expertResult != null ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_expertResult != null &&
                          i == _expertResultBubbleCount) {
                        return _expertResultCard(_expertResult!);
                      }
                      final idx =
                          (_expertResult != null &&
                              i > _expertResultBubbleCount)
                          ? i - 1
                          : i;
                      return AppReveal(
                        index: idx,
                        offset: const Offset(0, 10),
                        child: _expertBubbleWidget(_expertBubbles[idx]),
                      );
                    },
                  ),
                ),
        ),
        if (_expertError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: ErrorDisplayWidget(
              message: _expertError!,
              onRetry: _expertBubbles.isEmpty ? _startExpert : _replyExpert,
            ),
          ),
        _expertInputBar(followUp: _expertDone),
      ],
    );
  }

  /// 对话进行状态提示条。
  Widget _expertStatusBar() {
    final bool done = _expertDone;
    final String status;
    if (_expertLoading) {
      status = '正在思考…';
    } else if (done) {
      status = '讲解完成';
    } else if (_expertBubbles.isEmpty) {
      status = '等待题目';
    } else {
      status = '诊断推进中 · 第 $_expertRound 轮';
    }
    final Color c = (done && !_expertLoading)
        ? AppColors.accent
        : AppColors.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: AppMotion.resolve(context, AppMotion.standard),
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.7, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: Icon(
              _expertLoading
                  ? Icons.auto_awesome
                  : (done ? Icons.check_circle : Icons.tips_and_updates),
              key: ValueKey<String>(status),
              size: 14,
              color: c,
            ),
          ),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: AppMotion.resolve(context, AppMotion.standard),
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.4),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              status,
              key: ValueKey<String>(status),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 专家模式空状态引导。
  Widget _expertEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: AppColors.secondarySystem,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '专家模式 · 多轮追问，对症讲解',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '输入题目，专家会先追问你的思路和卡点\n信息足够后再个性化讲解',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  /// iMessage 风格对话气泡（用户蓝 / AI 灰），AI 追问附带可点击选择题选项。
  Widget _expertBubbleWidget(_ExpertBubble b) {
    return Align(
      alignment: b.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: b.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            decoration: BoxDecoration(
              color: b.isUser
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.72),
              border: b.isUser
                  ? null
                  : Border.all(color: Colors.black.withValues(alpha: 0.06)),
              borderRadius: BorderRadius.circular(12).copyWith(
                bottomRight: b.isUser ? const Radius.circular(4) : null,
                bottomLeft: b.isUser ? null : const Radius.circular(4),
              ),
            ),
            child: Text(
              b.content,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: b.isUser ? Colors.white : AppColors.foreground,
              ),
            ),
          ),
          if (b.options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...b.options.asMap().entries.map(
                    (e) => _optionButton(
                      '${'ABCDE'[e.key % 5]}. ${e.value}',
                      () => _replyExpert(e.value),
                    ),
                  ),
                  // 每题都提供"其他"：可自由输入自己的情况
                  _optionButton(
                    '… 其他（自行输入）',
                    () => _promptFreeInput(),
                    emphasized: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// "其他"自由输入弹窗：学生自定义回答，随后按回答推进决策树。
  Future<void> _promptFreeInput() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('补充你的情况'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '自由描述你的实际情况…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (text != null && text.isNotEmpty) {
      await _replyExpert(text);
    }
  }

  /// 选择题选项按钮：白卡 + 淡阴影，点击直接作为回答发送。
  /// [emphasized] 用于"其他"按钮（虚线边框 + 主色文字，提示可自由输入）。
  Widget _optionButton(
    String label,
    VoidCallback onTap, {
    bool emphasized = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: emphasized
              ? AppColors.primary.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: emphasized
                ? AppColors.primary.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: emphasized ? AppColors.primary : AppColors.foreground,
            fontWeight: emphasized ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 讲解结果结构化卡片（错题订正模板 7 段：错因 + 正确答案 + 分步解析 + 错因分析 + 知识点回顾 + 易错警示 + 变式训练 + 档案）。
  Widget _expertResultCard(Map<String, dynamic> result) {
    final explanation = result['explanation'];
    if (explanation is! Map<String, dynamic>) {
      return const SizedBox.shrink();
    }
    String g(String k) => explanation[k]?.toString() ?? '';
    final errorType = g('error_type');
    final difficulty = g('difficulty');
    final kps =
        (explanation['knowledge_points'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final hasTemplate =
        g('title').isNotEmpty ||
        g('step_analysis').isNotEmpty ||
        g('correct_answer').isNotEmpty;
    // 原题：processed_question.question_text，缺失则空（不折叠）
    final pq = result['processed_question'];
    final originalQuestion = pq is Map<String, dynamic>
        ? (pq['question_text']?.toString() ?? '')
        : '';

    final children = <Widget>[
      if (errorType.isNotEmpty || difficulty.isNotEmpty) ...[
        Wrap(
          spacing: 6,
          children: [
            if (errorType.isNotEmpty)
              Chip(
                label: Text('错因：$errorType'),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  color: AppColors.error,
                ),
                backgroundColor: AppColors.error.withValues(alpha: 0.08),
              ),
            if (difficulty.isNotEmpty)
              Chip(
                label: Text('难度：$difficulty'),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                ),
                backgroundColor: AppColors.primary.withValues(alpha: 0.08),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      if (hasTemplate)
        ..._templateSections(
          title: g('title'),
          correctAnswer: g('correct_answer'),
          stepAnalysis: g('step_analysis'),
          errorAnalysis: g('error_analysis'),
          knowledgeReview: g('knowledge_review'),
          warning: g('warning'),
          variation: g('variation'),
          archive: g('archive'),
          originalQuestion: originalQuestion,
          imageBase64: _expertImageBase64 ?? '',
        )
      else ...[
        _card('专家讲解', g('analysis')),
        const SizedBox(height: 12),
        _card('正确解法', g('correct_solution')),
      ],
      if (kps.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('关联知识点', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: kps.map((kp) => Chip(label: Text(kp))).toList(),
        ),
      ],
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppPressScale(
            pressedScale: 0.864,
            enabled: !_expertLoading,
            child: FilledButton.tonalIcon(
              onPressed: _expertLoading ? null : _resetExpert,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('完成，问下一题'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// 快速版结果区：优先渲染错题订正 7 段模板，旧数据 fallback 到题目分析/正确解法。
  List<Widget> _buildQuickResult() {
    final r = _guidanceResult;
    final hasTemplate =
        r != null &&
        (r.title.isNotEmpty ||
            r.stepAnalysis.isNotEmpty ||
            r.correctAnswer.isNotEmpty);
    return [
      Chip(label: Text('难度: $_difficulty')),
      const SizedBox(height: 12),
      if (hasTemplate)
        ..._templateSections(
          title: r.title,
          correctAnswer: r.correctAnswer,
          stepAnalysis: r.stepAnalysis,
          errorAnalysis: r.errorAnalysis,
          knowledgeReview: r.knowledgeReview,
          warning: r.warning,
          variation: r.variation,
          archive: r.archive,
          originalQuestion: _originalQuestion,
          imageBase64: _questionImageBase64 ?? '',
        )
      else ...[
        _card('题目分析', _analysis ?? ''),
        const SizedBox(height: 12),
        _card('正确解法', _solution ?? ''),
      ],
      const SizedBox(height: 12),
      Text('关联知识点', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        children: _knowledgePoints.map((kp) => Chip(label: Text(kp))).toList(),
      ),
      for (final (q, a) in _quickFollowUps) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Card(
            color: AppColors.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '追问：$q',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(a, style: const TextStyle(fontSize: 14, height: 1.5)),
          ),
        ),
      ],
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.tonalIcon(
            onPressed: _loading ? null : _resetQuick,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('完成，问下一题'),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ];
  }

  /// 错题订正模板 7 段卡片（快速版 / 专家版共用）。
  /// [originalQuestion] 非空时，标题卡可点击展开显示原题。
  List<Widget> _templateSections({
    required String title,
    required String correctAnswer,
    required String stepAnalysis,
    required String errorAnalysis,
    required String knowledgeReview,
    required String warning,
    required String variation,
    required String archive,
    String originalQuestion = '',
    String imageBase64 = '',
  }) {
    final list = <Widget>[];
    if (title.isNotEmpty) {
      list.add(_titleCard(title, originalQuestion, imageBase64: imageBase64));
      list.add(const SizedBox(height: 8));
    }
    if (correctAnswer.isNotEmpty) {
      list.add(_sectionCard('1. 本题正确答案', correctAnswer));
      list.add(const SizedBox(height: 8));
    }
    if (stepAnalysis.isNotEmpty) {
      list.add(_sectionCard('2. 标准分步解析', stepAnalysis));
      list.add(const SizedBox(height: 8));
    }
    if (errorAnalysis.isNotEmpty) {
      list.add(_sectionCard('3. 精准错因分析', errorAnalysis));
      list.add(const SizedBox(height: 8));
    }
    if (knowledgeReview.isNotEmpty) {
      list.add(_sectionCard('4. 核心知识点回顾', knowledgeReview));
      list.add(const SizedBox(height: 8));
    }
    if (warning.isNotEmpty) {
      list.add(_sectionCard('5. 本题易错警示', warning));
      list.add(const SizedBox(height: 8));
    }
    if (variation.isNotEmpty) {
      list.add(_sectionCard('6. 举一反三·变式训练', variation));
      list.add(const SizedBox(height: 8));
    }
    if (archive.isNotEmpty) {
      list.add(_sectionCard('7. 错题档案信息', archive, muted: true));
      list.add(const SizedBox(height: 8));
    }
    return list;
  }

  /// 模板标题卡：点击可展开显示原题（默认折叠）；有发送的原题图片时一并展示。
  Widget _titleCard(
    String title,
    String originalQuestion, {
    String imageBase64 = '',
  }) {
    // 无原题文本也无图片 → 普通卡
    if (originalQuestion.isEmpty && imageBase64.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: const Icon(
          Icons.menu_book_outlined,
          size: 20,
          color: AppColors.primary,
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        children: [
          if (originalQuestion.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.secondarySystem,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                originalQuestion,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.foreground,
                ),
              ),
            ),
          if (imageBase64.isNotEmpty) ...[
            if (originalQuestion.isNotEmpty) const SizedBox(height: 10),
            // 发送的原题图片（与错题本详情页一致：剥离 data: 前缀后解码）
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Image.memory(
                  base64Decode(dataImageBase64(imageBase64)),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 模板单段卡片。
  Widget _sectionCard(String label, String content, {bool muted = false}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            muted
                ? Text(
                    content,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.mutedForeground,
                    ),
                  )
                : StyledMarkdown(data: content),
          ],
        ),
      ),
    );
  }

  /// 专家版底部输入区（题目阶段可传图 / 追问阶段回答问题 / 讲解后继续追问）。
  Widget _expertInputBar({bool followUp = false}) {
    final bool initial = _expertBubbles.isEmpty;
    final VoidCallback onSend;
    final String hint;
    if (initial) {
      onSend = _startExpert;
      hint = '输入题目，专家将多轮追问...';
    } else if (followUp) {
      onSend = _expertFollowUp;
      hint = '就这道题继续追问...';
    } else {
      onSend = _replyExpert;
      hint = '回答专家的追问...';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (followUp) ...[
                  OutlinedButton.icon(
                    onPressed: _expertLoading ? null : _resetExpert,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('完成'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      // Enter = 发送；Shift+Enter = 换行
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed) {
                        onSend();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controller,
                      maxLines: 3,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      decoration: InputDecoration(
                        hintText: hint,
                        filled: true,
                        fillColor: AppColors.secondarySystem,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (initial) ...[
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    tooltip: '上传图片',
                    onPressed: _pickImage,
                  ),
                  const SizedBox(width: 4),
                ],
                CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: IconButton(
                    icon: _expertLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _expertLoading ? null : onSend,
                  ),
                ),
              ],
            ),
            if (initial && _pickedImage != null) ...[
              const SizedBox(height: 8),
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      _pickedImage!.path,
                      height: 100,
                      width: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => setState(() => _pickedImage = null),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 专家版对话气泡（展示用）。
/// 专家版诊断决策树节点（前端驱动，保证逐层推进、不跳层不重复）。
enum _ExpertNode {
  root, // 第1层：处理到哪一步
  aSimilar, // A 分支：类似题目会写吗
  bWhy, // B 分支：为什么没有进行计算
  cQuantity, // C 分支：算出了哪些量
  cWhy, // C 分支第3层：为什么后面算不出来了
  dWhich, // D 分支：检查哪一个数据算错了
  // 叶子节点（到达即讲解）
  aLeafDiff,
  aLeafGeneral,
  aLeafBasic,
  bLeafFormula,
  bLeafUse,
  bLeafStart,
  cLeafNum,
  cLeafEq,
  cLeafMotion,
  cLeafEqn,
  dLeaf,
}

class _ExpertBubble {
  final bool isUser;
  final String content;
  final List<String> options; // AI 追问附带的选择题选项（可点击直接回答）
  const _ExpertBubble({
    required this.isUser,
    required this.content,
    this.options = const [],
  });
}
