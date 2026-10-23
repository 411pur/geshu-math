/// A single node in the physics knowledge structure.
class KnowledgeNode {
  final String id;
  final String? parentId;
  final String title;
  final String? description;
  final int level;
  final int sortOrder;
  final String source;
  final int createdAt;
  final int updatedAt;

  const KnowledgeNode({
    required this.id,
    this.parentId,
    required this.title,
    this.description,
    required this.level,
    this.sortOrder = 0,
    this.source = 'static',
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Graph data for the spider-web radial view.
class GraphData {
  final List<KnowledgeNode> nodes;
  final List<GraphEdge> edges;

  const GraphData({required this.nodes, this.edges = const []});
}

/// An edge between two KnowledgeNodes in the graph.
class GraphEdge {
  final String fromId;
  final String toId;

  const GraphEdge({required this.fromId, required this.toId});
}

/// Recursive tree node for the hierarchical view.
class TreeNode {
  final String id;
  final String title;
  final int level;
  final List<TreeNode> children;

  const TreeNode({
    required this.id,
    required this.title,
    required this.level,
    this.children = const [],
  });
}