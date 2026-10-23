import '../../database/data_store.dart';
import '../../../domain/entities/knowledge_entity.dart';

class KnowledgeDataSource {
  final DataStore _store;
  KnowledgeDataSource(this._store);
  List<KnowledgeNode> getAll() => _store.getAllNodes();
  List<KnowledgeNode> getRoots() => _store.getRootNodes();
  List<KnowledgeNode> getChildrenOf(String parentId) => _store.getChildrenOf(parentId);
  KnowledgeNode? getById(String id) => _store.getNodeById(id);
  List<KnowledgeNode> search(String query) => _store.searchNodes(query);
  void addNode(KnowledgeNode node) => _store.addNode(node);
  int count() => _store.nodeCount;
}