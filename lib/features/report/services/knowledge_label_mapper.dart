import 'dart:convert';
import '../../../domain/entities/knowledge_entity.dart';
import '../../../domain/entities/wrong_question_entity.dart';

/// 知识标签匹配器：
/// 用本地数学知识图谱把错题的粗标签（tags/knowledge_points/topic）
/// 细化成「模块→章→节→知识点」的完整路径标签。
class KnowledgeLabelMapper {
  final List<KnowledgeNode> _graph;

  KnowledgeLabelMapper(this._graph);

  /// 清洗节点标题：去掉 "1. " "第一章 " 等编号前缀
  String _cleanTitle(String t) {
    var s = t.trim();
    s = s.replaceFirst(RegExp(r'^[\d一二三四五六七八九十]+[\.、]?\s*'), '');
    s = s.replaceFirst(RegExp(r'^第[\d一二三四五六七八九十]+章\s*'), '');
    return s.trim();
  }

  /// 解析错题 guidanceResultJson 里的 knowledge_points
  List<String> _knowledgePointsOf(WrongQuestion wq) {
    final raw = wq.guidanceResultJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      final kps = map['knowledge_points'];
      if (kps is List) return kps.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } catch (_) {}
    return const [];
  }

  /// 解析错题 tags（tagsJson）
  List<String> _tagsOf(WrongQuestion wq) {
    final raw = wq.tagsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = json.decode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } catch (_) {}
    return const [];
  }

  /// 回溯父链，得到完整节点路径（根 → 末级）。
  List<KnowledgeNode> _nodePathOf(KnowledgeNode node) {
    final path = <KnowledgeNode>[];
    KnowledgeNode? cur = node;
    while (cur != null) {
      path.insert(0, cur);
      final pid = cur.parentId;
      if (pid == null) break;
      cur = _graph.where((n) => n.id == pid).firstOrNull;
    }
    return path;
  }

  /// 对几个候选标签，生成所有匹配到的知识路径（节点级，含 id）。
  ///
  /// 供弱点统计 / 图谱关联错题使用；[match] 只保留标题版本。
  List<List<KnowledgeNode>> matchNodes(WrongQuestion wq) {
    final kps = _knowledgePointsOf(wq);
    final tags = _tagsOf(wq);
    final topic = wq.topic ?? '';

    final result = <List<KnowledgeNode>>[];
    final seen = <String>{};

    void addPath(KnowledgeNode node) {
      final p = _nodePathOf(node);
      final key = p.map((n) => n.id).join('>');
      if (seen.contains(key)) return;
      seen.add(key);
      result.add(p);
    }

    // 优先级：完全匹配 > 子串匹配；权重：kps > tags > topic
    void tryMatch(String kw, int priority) {
      if (kw.isEmpty || kw.length < 2) return;
      final ckw = kw.trim();
      // 完全匹配优先
      KnowledgeNode? exact;
      for (final n in _graph) {
        if (_cleanTitle(n.title) == ckw) {
          exact = n;
          break;
        }
      }
      if (exact != null) {
        if (priority >= 2) addPath(exact);
        return;
      }
      // 有实际长度的关键词做子串匹配（≥3字且非"平面几何"这类泛词时）
      if (ckw.length >= 3 && !_isGeneric(ckw)) {
        KnowledgeNode? best;
        for (final n in _graph) {
          final ct = _cleanTitle(n.title);
          if (ct.isEmpty || ct.length < 2) continue;
          if (ct.contains(ckw) || (ckw.contains(ct) && ct.length >= 3)) {
            if (best == null || n.level > best.level) best = n;
          }
        }
        if (best != null) addPath(best);
      }
    }

    // 按优先级：kps(3) > tags(2) > topic(1)
    for (final kw in kps) {
      tryMatch(kw, 3);
    }
    for (final kw in tags) {
      tryMatch(kw, 2);
    }
    tryMatch(topic, 1);

    return result;
  }

  /// 对几个候选标签，生成所有匹配路径
  /// 返回形如 [['函数与导数','二次函数','二次函数的最值'], ...]
  List<List<String>> match(WrongQuestion wq) {
    final result =
        matchNodes(wq).map((p) => p.map((n) => n.title).toList()).toList();
    // 没有匹配到图谱节点时，用 topic 本身兜底（保留一级标签，无节点 id）
    if (result.isEmpty && (wq.topic ?? '').isNotEmpty) {
      result.add([wq.topic!]);
    }
    return result;
  }

  bool _isGeneric(String kw) =>
      kw == '数与代数' ||
      kw == '方程与不等式' ||
      kw == '函数' ||
      kw == '函数与导数' ||
      kw == '平面几何' ||
      kw == '立体几何' ||
      kw == '解析几何' ||
      kw == '数列' ||
      kw == '向量与复数' ||
      kw == '概率统计' ||
      kw == '导数';
}