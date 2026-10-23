import '../../domain/entities/knowledge_entity.dart';
import '../datasources/local/knowledge_datasource.dart';

/// Business-logic layer for knowledge retrieval.
///
/// Translates flat DB rows into structured formats needed by
/// the graph and tree UI views.
class KnowledgeRepository {
  final KnowledgeDataSource _ds;

  KnowledgeRepository(this._ds);

  // ── Graph data ───────────────────────────────────────────

  /// Returns nodes + edges inferred from parentId relationships.
  Future<GraphData> getGraphData({String? rootId}) async {
    final all = _ds.getAll();

    // If rootId specified, filter to that subtree.
    final nodes = rootId != null
        ? _subtree(all, rootId)
        : all;

    // Infer edges: every non-root node → edge from parent to child.
    final edges = <GraphEdge>[];
    for (final node in nodes) {
      if (node.parentId != null) {
        edges.add(GraphEdge(fromId: node.parentId!, toId: node.id));
      }
    }

    return GraphData(nodes: nodes, edges: edges);
  }

  // ── Tree data ────────────────────────────────────────────

  /// Builds a recursive tree from the root(s).
  Future<List<TreeNode>> getTreeData({String? rootId}) async {
    final all = _ds.getAll();
    final roots = rootId != null
        ? all.where((n) => n.id == rootId).toList()
        : all.where((n) => n.parentId == null).toList();

    return roots.map((r) => _buildTree(r, all)).toList();
  }

  // ── Search ───────────────────────────────────────────────

  Future<List<KnowledgeNode>> search(String query) async {
    return Future.value(_ds.search(query));
  }

  // ── Enrichment (Dify → new nodes) ────────────────────────

  Future<void> enrichFromDify(List<KnowledgeNode> newNodes) async {
    for (final node in newNodes) {
      _ds.addNode(node);
    }
  }

  // ── Helpers ──────────────────────────────────────────────

  /// Collect all nodes in the subtree rooted at [rootId].
  List<KnowledgeNode> _subtree(List<KnowledgeNode> all, String rootId) {
    final result = <KnowledgeNode>[];
    final root = all.where((n) => n.id == rootId).toList();
    result.addAll(root);

    final childIds = root.map((n) => n.id).toSet();
    final queue = childIds.toList();
    while (queue.isNotEmpty) {
      final parentId = queue.removeAt(0);
      final children = all.where((n) => n.parentId == parentId).toList();
      result.addAll(children);
      queue.addAll(children.map((c) => c.id));
    }
    return result;
  }

  /// Build a recursive tree node from [node].
  TreeNode _buildTree(KnowledgeNode node, List<KnowledgeNode> all) {
    final children = all
        .where((n) => n.parentId == node.id)
        .map((c) => _buildTree(c, all))
        .toList();
    return TreeNode(
      id: node.id,
      title: node.title,
      level: node.level,
      children: children,
    );
  }
}
