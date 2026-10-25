import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/wrong_question_entity.dart';
import '../../report/services/knowledge_label_mapper.dart';
import '../../wrong_question/providers/wrong_question_providers.dart';
import 'knowledge_providers.dart';

/// 单个知识点的弱点统计（加权错题分 + 关联错题）。
///
/// 分数口径（用户确认）：每道错题按掌握度加权
/// 未掌握=3 / 复习中=2 / 已掌握=1，计入它映射到的每个知识点（含父级链）。
///
/// 向下继承（用户确认）：标签命中上级节点时，上级红、下级不能是白的。
/// 展示分 = max(自身分, 父级展示分 × [_childFade])，从根到叶单次遍历，
/// 下级自然比上级淡一点点；关联错题列表同理继承（自身题在前，去重）。
///
/// 归一化口径（用户确认）：相对自己 —— 展示分最高的节点 = 1（最黑），无错题 = 0（白）。
class KnowledgeWeakness {
  /// 节点 id -> 展示分（已含向下继承）。
  final Map<String, double> scoreById;

  /// 展示分最高的节点得分（0 表示没有错题命中图谱）。
  final double maxScore;

  /// 节点 id -> 关联错题（自身的 + 从父级继承的，按 id 去重）。
  final Map<String, List<WrongQuestion>> mistakesByNodeId;

  /// 节点 id -> 仅自身直接命中的错题（不含继承），供 UI 区分展示。
  final Map<String, List<WrongQuestion>> ownById;

  const KnowledgeWeakness({
    required this.scoreById,
    required this.maxScore,
    required this.mistakesByNodeId,
    required this.ownById,
  });

  bool get isEmpty => maxScore <= 0;

  /// 相对归一化弱点度：0 = 无错题，1 = 自己最弱的知识点。
  double weaknessOf(String nodeId) {
    final s = scoreById[nodeId] ?? 0;
    if (maxScore <= 0) return 0;
    return (s / maxScore).clamp(0.0, 1.0);
  }
}

/// 下级继承上级展示分的衰减系数：父 × 0.7 = 子的下限，
/// 保证"上级红 ⇒ 下级一定不白"，且每深一级淡约三成。
const double _childFade = 0.7;

/// 遍历本地错题，用知识图谱把每道错题映射到知识点路径，累加弱点分，
/// 再沿树自上而下继承，保证父红子不白。
///
/// 数据量（本地几十道错题 × 几百个节点）远小于一次 LLM 调用的成本，
/// 每次打开图谱时重算即可，不需要持久化。
final knowledgeWeaknessProvider = FutureProvider<KnowledgeWeakness>((ref) async {
  final wqDs = ref.watch(wrongQuestionDataSourceProvider);
  final graphDs = ref.watch(knowledgeDataSourceProvider);

  final all = wqDs.getAllPaginated(limit: wqDs.count());
  final nodes = graphDs.getAll();
  if (nodes.isEmpty || all.isEmpty) {
    return const KnowledgeWeakness(
      scoreById: {},
      maxScore: 0,
      mistakesByNodeId: {},
      ownById: {},
    );
  }
  final mapper = KnowledgeLabelMapper(nodes);

  double masteryWeight(int mastery) => switch (mastery) {
        0 => 3.0,
        1 => 2.0,
        _ => 1.0,
      };

  // ── 第 1 步：沿匹配路径累加「自身分」（同时向父级链上传，与旧口径一致）──
  final ownScore = <String, double>{};
  final ownMistakes = <String, List<WrongQuestion>>{};

  for (final wq in all) {
    final paths = mapper.matchNodes(wq);
    for (final path in paths) {
      for (final node in path) {
        ownScore[node.id] = (ownScore[node.id] ?? 0) + masteryWeight(wq.mastery);
        ownMistakes.putIfAbsent(node.id, () => []).add(wq);
      }
    }
  }

  // ── 第 2 步：从根到叶单次遍历，向下继承 ──
  // 展示分 = max(自身分, 父级展示分 × _childFade)
  // 错题列表 = 自身 + 父级列表（按 id 去重，自身在前）
  final byId = {for (final n in nodes) n.id: n};
  final childrenOf = <String, List<String>>{};
  final roots = <String>[];
  for (final n in nodes) {
    final pid = n.parentId;
    if (pid == null || !byId.containsKey(pid)) {
      roots.add(n.id);
    } else {
      childrenOf.putIfAbsent(pid, () => []).add(n.id);
    }
  }

  List<WrongQuestion> mergedList(
    List<WrongQuestion> Function() own,
    List<WrongQuestion> parentList,
  ) {
    final seen = <Object>{};
    final out = <WrongQuestion>[];
    void addAll(List<WrongQuestion> list) {
      for (final wq in list) {
        final key = wq.id ?? identityHashCode(wq);
        if (seen.contains(key)) continue;
        seen.add(key);
        out.add(wq);
      }
    }

    addAll(own());
    addAll(parentList);
    return out;
  }

  final displayScore = <String, double>{};
  final displayMistakes = <String, List<WrongQuestion>>{};

  // 自上而下遍历（每个节点只有单一父节点，出栈时父级必已就绪）。
  final queue = List<String>.from(roots);
  final visited = <String>{};
  while (queue.isNotEmpty) {
    final id = queue.removeLast();
    if (!visited.add(id)) continue;
    final node = byId[id]!;
    final pid = node.parentId;
    final parentScore = (pid != null) ? displayScore[pid] ?? 0.0 : 0.0;
    final own = ownScore[id] ?? 0.0;
    displayScore[id] = own > parentScore * _childFade ? own : parentScore * _childFade;
    final List<WrongQuestion> parentList =
        (pid != null) ? displayMistakes[pid] ?? const [] : const [];
    displayMistakes[id] =
        mergedList(() => ownMistakes[id] ?? const [], parentList);
    for (final child in childrenOf[id] ?? const <String>[]) {
      queue.add(child);
    }
  }

  var maxScore = 0.0;
  for (final v in displayScore.values) {
    if (v > maxScore) maxScore = v;
  }

  return KnowledgeWeakness(
    scoreById: displayScore,
    maxScore: maxScore,
    mistakesByNodeId: displayMistakes,
    ownById: ownMistakes,
  );
});
