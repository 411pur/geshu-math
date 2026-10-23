import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/db_provider.dart';
import '../../../data/datasources/local/knowledge_datasource.dart';
import '../../../data/repositories/knowledge_repository.dart';
import '../../../domain/entities/knowledge_entity.dart';

/// Data source (thin DAO wrapper).
final knowledgeDataSourceProvider = Provider<KnowledgeDataSource>((ref) {
  final store = ref.watch(dataStoreProvider);
  return KnowledgeDataSource(store);
});

/// Business-logic repository.
final knowledgeRepositoryProvider = Provider<KnowledgeRepository>((ref) {
  final ds = ref.watch(knowledgeDataSourceProvider);
  return KnowledgeRepository(ds);
});

/// Graph data for the spider-web view.
final graphDataProvider = FutureProvider.family<GraphData, String?>((ref, rootId) async {
  final repo = ref.watch(knowledgeRepositoryProvider);
  return repo.getGraphData(rootId: rootId);
});

/// Tree data for the hierarchical view.
final treeDataProvider = FutureProvider.family<List<TreeNode>, String?>((ref, rootId) async {
  final repo = ref.watch(knowledgeRepositoryProvider);
  return repo.getTreeData(rootId: rootId);
});