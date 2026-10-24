import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/tree_node_widget.dart';
import '../widgets/graph_painter.dart' show weaknessHeatColor;
import '../providers/knowledge_providers.dart';
import '../providers/knowledge_weakness_provider.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_display_widget.dart';

class KnowledgeTreePage extends ConsumerStatefulWidget {
  const KnowledgeTreePage({super.key});

  @override
  ConsumerState<KnowledgeTreePage> createState() => _KnowledgeTreePageState();
}

class _KnowledgeTreePageState extends ConsumerState<KnowledgeTreePage> {
  /// 弱点热力着色开关；与图谱页同一套口径（白→红→黑）。
  bool _heatView = false;

  Color? Function(String)? _heatColorOf() {
    if (!_heatView) return null;
    final weakness = ref.read(knowledgeWeaknessProvider).asData?.value;
    if (weakness == null || weakness.isEmpty) return null;
    return (String id) => weaknessHeatColor(weakness.weaknessOf(id));
  }

  @override
  Widget build(BuildContext context) {
    // watch 让错题数据变化时树色跟着刷新；取色在 _heatColorOf 里完成。
    final weakness = ref.watch(knowledgeWeaknessProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('知识树'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.local_fire_department,
              color: _heatView ? weaknessHeatColor(0.5) : null,
            ),
            tooltip: _heatView ? '关闭弱点视图' : '弱点视图（白→红→黑，红=最弱）',
            onPressed: () => setState(() => _heatView = !_heatView),
          ),
          IconButton(
            icon: const Icon(Icons.hub),
            tooltip: '图谱视图',
            onPressed: () => context.push('/home/graph'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_heatView) _buildHeatLegend(weakness),
          Expanded(
            child: treePageBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatLegend(KnowledgeWeakness? weakness) {
    final hasData = weakness != null && !weakness.isEmpty;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Text('弱点',
              style: TextStyle(
                  color: muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Container(
            width: 130,
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                colors: [
                  weaknessHeatColor(0),
                  weaknessHeatColor(0.5),
                  weaknessHeatColor(1),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(hasData ? '0 道 → 最弱' : '暂无错题数据',
              style: TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget treePageBody() {
    final treeAsync = ref.watch(treeDataProvider(null));

    return treeAsync.when(
      loading: () => const LoadingIndicator(message: '加载知识树...'),
      error: (err, _) => ErrorDisplayWidget(
        message: err.toString(),
        onRetry: () => ref.invalidate(treeDataProvider(null)),
      ),
      data: (roots) {
        if (roots.isEmpty) {
          return const Center(child: Text('暂无知识数据'));
        }
        final heatColorOf = _heatColorOf();
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: roots
                .map((root) => TreeNodeWidget(
                      node: root,
                      heatColorOf: heatColorOf,
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}
