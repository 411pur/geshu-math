import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/tree_node_widget.dart';
import '../providers/knowledge_providers.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_display_widget.dart';

class KnowledgeTreePage extends ConsumerWidget {
  const KnowledgeTreePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treeAsync = ref.watch(treeDataProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: const Text('知识树'),
        actions: [
          IconButton(
            icon: const Icon(Icons.hub),
            tooltip: '图谱视图',
            onPressed: () => context.push('/home/graph'),
          ),
        ],
      ),
      body: treeAsync.when(
        loading: () => const LoadingIndicator(message: '加载知识树...'),
        error: (err, _) => ErrorDisplayWidget(
          message: err.toString(),
          onRetry: () => ref.invalidate(treeDataProvider(null)),
        ),
        data: (roots) {
          if (roots.isEmpty) {
            return const Center(child: Text('暂无知识数据'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: roots
                  .map((root) => TreeNodeWidget(node: root))
                  .toList(),
            ),
          );
        },
      ),
    );
  }
}
