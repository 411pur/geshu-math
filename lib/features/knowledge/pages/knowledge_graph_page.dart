import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/graph_painter.dart';
import '../providers/knowledge_providers.dart';
import '../providers/knowledge_weakness_provider.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/knowledge_entity.dart';
import '../../../domain/entities/wrong_question_entity.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_display_widget.dart';
import '../../wrong_question/pages/wrong_question_detail_page.dart';

class KnowledgeGraphPage extends ConsumerStatefulWidget {
  const KnowledgeGraphPage({super.key});

  @override
  ConsumerState<KnowledgeGraphPage> createState() => _KnowledgeGraphPageState();
}

class _KnowledgeGraphPageState extends ConsumerState<KnowledgeGraphPage>
    with SingleTickerProviderStateMixin {
  KnowledgeNode? _selectedNode;

  /// 详情面板当前展示的节点。关闭时保留，好让退场动画有内容可播。
  KnowledgeNode? _sheetNode;

  String? _subjectFilter;
  int _maxLevel = 2; // 默认显示 模块+章（L0+L1）；L2 显示节，L3 末级
  final Set<String> _expandedIds = {};

  /// 弱点热力视图：节点颜色从科目色切换为 白→红→黑。
  bool _heatView = false;

  /// 命中信息（屏幕坐标 + 深度 + 世界坐标），由 painter 每帧回填。
  final Map<String, NodeHit> _hits = {};

  /// 图表变换（记录缩放/平移，点击命中时换算坐标）
  final TransformationController _transformCtrl = TransformationController();

  // ── 立体视角状态 ────────────────────────────────────────
  bool _use3D = true;
  double _yaw = -0.42;
  double _pitch = 0.17;
  double _viewScale = 1.0;
  String? _hoveredId;

  /// 旋转手势用裸指针监听实现，避免和 InteractiveViewer 抢手势。
  int _activePointers = 0;
  Offset? _lastPointer;

  /// "飞向节点"的视角补间。
  late final AnimationController _flyCtrl;
  Animation<double>? _yawAnim;
  Animation<double>? _pitchAnim;

  @override
  void initState() {
    super.initState();
    _flyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..addListener(_onFlyTick);
    _transformCtrl.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformCtrl.removeListener(_onTransformChanged);
    _flyCtrl.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  void _onFlyTick() {
    final ya = _yawAnim;
    final pa = _pitchAnim;
    if (ya == null || pa == null || !mounted) return;
    setState(() {
      _yaw = ya.value;
      _pitch = pa.value;
    });
  }

  void _onTransformChanged() {
    final s = _transformCtrl.value.getMaxScaleOnAxis();
    if ((s - _viewScale).abs() > 0.02 && mounted) {
      setState(() => _viewScale = s);
    }
  }

  // ── 命中测试 ────────────────────────────────────────────

  /// 屏幕坐标 -> 画布坐标（InteractiveViewer 变换的逆）。
  Offset _toCanvas(Offset local) {
    final inv = Matrix4.inverted(_transformCtrl.value);
    return MatrixUtils.transformPoint(inv, local);
  }

  /// 找出画布坐标下最靠前（depth 最小）的命中节点。
  String? _hitAt(Offset canvasPos) {
    String? bestId;
    NodeHit? best;
    for (final entry in _hits.entries) {
      final h = entry.value;
      // 命中半径取屏幕空间的固定值下限，保证缩得很小时依然点得到。
      final reach = math.max(h.radius + 8.0, 15.0);
      if ((canvasPos - h.position).distance > reach) continue;
      if (best == null || h.depth < best.depth) {
        best = h;
        bestId = entry.key;
      }
    }
    return bestId;
  }

  void _onTapUp(TapUpDetails details) {
    final id = _hitAt(_toCanvas(details.localPosition));
    if (id == null) {
      setState(() => _selectedNode = null);
      return;
    }
    final graph = ref.read(graphDataProvider(_subjectFilter)).asData?.value;
    if (graph == null) return;

    KnowledgeNode? node;
    for (final n in graph.nodes) {
      if (n.id == id) {
        node = n;
        break;
      }
    }
    if (node == null) return;

    final target = node;
    setState(() {
      // 点击节点：若有子节点且未到末级，则展开/收起其子级；否则选中
      final hasChildren = graph.edges.any((e) => e.fromId == target.id);
      if (hasChildren && target.level < 3) {
        if (_expandedIds.contains(target.id)) {
          _expandedIds.remove(target.id);
        } else {
          _expandedIds.add(target.id);
          if (target.level + 1 > _maxLevel) _maxLevel = target.level + 1;
        }
      }
      _selectedNode = target;
      _sheetNode = target;
    });
  }

  void _onHover(PointerHoverEvent event) {
    // MouseRegion 位于 InteractiveViewer 的子级，localPosition 已经是画布坐标。
    final id = _hitAt(event.localPosition);
    if (id != _hoveredId && mounted) {
      setState(() => _hoveredId = id);
    }
  }

  // ── 视角 ────────────────────────────────────────────────

  void _resetView() {
    _animateViewTo(-0.42, 0.17);
  }

  /// 把 yaw/pitch 补间到目标值（yaw 走最短角路径）。
  void _animateViewTo(double targetYaw, double targetPitch) {
    final fromYaw = _yaw;
    final fromPitch = _pitch;

    var delta = targetYaw - fromYaw;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }

    final curve = CurvedAnimation(parent: _flyCtrl, curve: Curves.easeOutCubic);
    _yawAnim = Tween<double>(begin: fromYaw, end: fromYaw + delta).animate(curve);
    _pitchAnim = Tween<double>(begin: fromPitch, end: targetPitch).animate(curve);
    _flyCtrl.forward(from: 0);
  }

  /// 旋转视角，让某个节点转到正对相机的位置。
  void _flyToNode(KnowledgeNode node) {
    final hit = _hits[node.id];
    if (hit == null) return;
    if (!_use3D) return;

    final p = hit.world;
    final planar = math.sqrt(p.x * p.x + p.z * p.z);
    if (planar < 1) return;

    // yaw 使得 (x,z) 转到 -z 方向（离相机最近）；pitch 使其落到画面中线。
    final targetYaw = math.atan2(p.x, p.z) + math.pi;
    final targetPitch = (-math.atan2(p.y, planar)).clamp(-1.15, 1.15).toDouble();
    _animateViewTo(targetYaw, targetPitch);
  }

  /// 展开目标节点所需的所有祖先，使其进入可见集合。
  Future<void> _revealNode(KnowledgeNode node, GraphData graph) async {
    final byId = {for (final n in graph.nodes) n.id: n};
    var cur = node;
    var guard = 0;
    var changed = false;

    while (cur.parentId != null && guard++ < 16) {
      final parent = byId[cur.parentId];
      if (parent == null) break;
      if (parent.level >= 1 && !_expandedIds.contains(parent.id)) {
        _expandedIds.add(parent.id);
        changed = true;
      }
      cur = parent;
    }
    if (node.level > _maxLevel) {
      _maxLevel = node.level.clamp(1, 3);
      changed = true;
    }
    if (changed && mounted) {
      setState(() {});
      // 等一帧让 painter 用新布局回填 _hits，再计算目标视角。
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    if (!mounted) return;
    setState(() {
      _selectedNode = node;
      _sheetNode = node;
    });
    _flyToNode(node);
  }

  // ── 层级控制 ────────────────────────────────────────────

  /// 展开/收起层级
  void _adjustLevel(int delta) {
    setState(() {
      _maxLevel = (_maxLevel + delta).clamp(1, 3);
      // 收起层级时清空过深的手动展开
      if (_maxLevel < 3) _expandedIds.clear();
    });
  }

  /// Subject filter tabs —— 深色玻璃胶囊，和画布同一套视觉语言。
  Widget _buildSubjectTabs() {
    final categories = [
      null, // 全部
      'number-and-algebra',
      'equation-inequality',
      'set-function-derivative',
      'trigonometry',
      'sequence',
      'plane-geometry',
      'solid-geometry',
      'vector-complex',
      'analytic-geometry',
      'counting-probability-stats',
    ];
    final labels = [
      '全部',
      '数与代数',
      '方程与不等式',
      '函数与导数',
      '三角函数',
      '数列',
      '平面几何',
      '立体几何',
      '向量与复数',
      '解析几何',
      '概率统计',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: List.generate(categories.length, (i) {
          final cat = categories[i];
          final selected = _subjectFilter == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppPressScale(
              pressedScale: 0.94,
              child: Material(
                color: Colors.white.withValues(alpha: selected ? 0.16 : 0.05),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => setState(() {
                    _subjectFilter = cat;
                    _expandedIds.clear();
                    _maxLevel = 2;
                    _selectedNode = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: selected ? 0.30 : 0.08,
                        ),
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.68),
                        fontSize: 12.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// 层级控制栏
  Widget _buildLevelBar() {
    final levelNames = {1: '模块', 2: '模块+章', 3: '模块+章+节'};
    final iconColor = Colors.white.withValues(alpha: 0.78);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppPressScale(
            pressedScale: 0.86,
            enabled: _maxLevel > 1,
            child: IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              color: iconColor,
              tooltip: '收起一层',
              visualDensity: VisualDensity.compact,
              onPressed: _maxLevel <= 1 ? null : () => _adjustLevel(-1),
            ),
          ),
          Text(
            '当前层级：${levelNames[_maxLevel] ?? _maxLevel}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          AppPressScale(
            pressedScale: 0.86,
            enabled: _maxLevel < 3,
            child: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              color: iconColor,
              tooltip: '展开一层',
              visualDensity: VisualDensity.compact,
              onPressed: _maxLevel >= 3 ? null : () => _adjustLevel(1),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _use3D ? '拖拽旋转' : '拖拽平移',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── 画布 ────────────────────────────────────────────────

  Widget _buildCanvas(GraphData graph, KnowledgeWeakness? weakness) {
    return Listener(
      onPointerDown: (event) {
        _activePointers++;
        _lastPointer = event.localPosition;
      },
      onPointerMove: (event) {
        final last = _lastPointer;
        // 只有单指/单点拖拽才旋转；双指留给 InteractiveViewer 缩放。
        if (_use3D && _activePointers == 1 && last != null) {
          final d = event.localPosition - last;
          setState(() {
            _yaw = _wrapAngle(_yaw + d.dx * 0.0075);
            _pitch = (_pitch + d.dy * 0.0055).clamp(-1.15, 1.15).toDouble();
          });
        }
        _lastPointer = event.localPosition;
      },
      onPointerUp: (_) {
        _activePointers = math.max(0, _activePointers - 1);
        _lastPointer = null;
      },
      onPointerCancel: (_) {
        _activePointers = math.max(0, _activePointers - 1);
        _lastPointer = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        child: InteractiveViewer(
          transformationController: _transformCtrl,
          minScale: 0.3,
          maxScale: 3.0,
          // 立体模式下拖拽用于旋转视角，因此关闭平移；平面模式保持原有平移。
          panEnabled: !_use3D,
          child: MouseRegion(
            onHover: _onHover,
            onExit: (_) {
              if (_hoveredId != null) setState(() => _hoveredId = null);
            },
            child: SizedBox.expand(
              child: CustomPaint(
                painter: KnowledgeGraphPainter(
                  graphData: graph,
                  selectedNodeId: _selectedNode?.id,
                  hoveredNodeId: _hoveredId,
                  maxLevel: _maxLevel,
                  expandedIds: _expandedIds,
                  use3D: _use3D,
                  yaw: _yaw,
                  pitch: _pitch,
                  viewScale: _viewScale,
                  heatMode: _heatView,
                  weakness: weakness,
                  // 弱点视图直接看全局网络：绕过折叠门控，所有层级全展开；
                  // 关掉后恢复原来的层级/手动展开状态。
                  showAllLevels: _heatView,
                  positionsCallback: (hits) {
                    _hits.clear();
                    _hits.addAll(hits);
                  },
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _wrapAngle(double a) {
    var v = a % (2 * math.pi);
    if (v > math.pi) v -= 2 * math.pi;
    if (v < -math.pi) v += 2 * math.pi;
    return v;
  }

  /// 在深色画布上渲染浅色文字（加载 / 出错态复用共享组件）。
  Widget _onDark(Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: scheme.copyWith(
          onSurface: Colors.white,
          onSurfaceVariant: Colors.white.withValues(alpha: 0.72),
        ),
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final graphAsync = ref.watch(graphDataProvider(_subjectFilter));
    final weakness = ref.watch(knowledgeWeaknessProvider).asData?.value;

    return Scaffold(
      // 整个知识图谱页做成一块连续的深色沉浸面：页面顶栏 / 筛选条 / 层级条 /
      // 画布共用同一套底色与渐变。原先白色顶栏压着深色画布，是"割裂感"的来源。
      backgroundColor: AppColors.canvasCore,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          '知识图谱',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          AppPressScale(
            pressedScale: 0.86,
            child: IconButton(
              icon: Icon(
                Icons.local_fire_department,
                color: _heatView ? weaknessHeatColor(0.5) : Colors.white,
              ),
              tooltip: _heatView ? '关闭弱点视图' : '弱点视图（白→红→黑，红=最弱）',
              onPressed: () => setState(() => _heatView = !_heatView),
            ),
          ),
          AppPressScale(
            pressedScale: 0.86,
            child: IconButton(
              icon: Icon(_use3D ? Icons.view_in_ar : Icons.grid_view_rounded),
              tooltip: _use3D ? '切换到平面视图' : '切换到立体视图',
              onPressed: () => setState(() {
                _use3D = !_use3D;
                _hoveredId = null;
              }),
            ),
          ),
          if (_use3D)
            AppPressScale(
              pressedScale: 0.86,
              child: IconButton(
                icon: const Icon(Icons.center_focus_strong),
                tooltip: '重置视角',
                onPressed: _resetView,
              ),
            ),
          AppPressScale(
            pressedScale: 0.86,
            child: IconButton(
              icon: const Icon(Icons.list),
              tooltip: '树状图',
              onPressed: () => context.push('/home/tree'),
            ),
          ),
          AppPressScale(
            pressedScale: 0.86,
            child: IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: _showSearchDialog,
            ),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.canvasCore, AppColors.canvasEdge],
          ),
        ),
        child: Column(
          children: [
            _buildSubjectTabs(),
            _buildLevelBar(),
            if (_heatView) _buildHeatLegend(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: graphAsync.when(
                      loading: () => _onDark(
                        const LoadingIndicator(message: '加载知识图谱...'),
                      ),
                      error: (err, _) => _onDark(
                        ErrorDisplayWidget(
                          message: err.toString(),
                          onRetry: () => ref
                              .invalidate(graphDataProvider(_subjectFilter)),
                        ),
                      ),
                      data: (graph) {
                        if (graph.nodes.isEmpty) {
                          return const Center(child: Text('暂无知识数据'));
                        }
                        return _buildCanvas(graph, weakness);
                      },
                    ),
                  ),
                  // 详情面板浮在画布之上（而不是用 Scaffold.bottomSheet）：
                  // bottomSheet 会压缩 body 高度，点节点时整张图会重排跳一下；
                  // 放进 Stack 后画布尺寸恒定，面板滑入完全不影响图谱。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _detailOverlay(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 详情面板：浮在画布之上的玻璃卡片，带入场 / 退场动画。
  Widget _detailOverlay() {
    final node = _sheetNode;
    if (node == null) return const SizedBox.shrink();
    final open = _selectedNode != null;

    return IgnorePointer(
      ignoring: !open,
      child: AnimatedSlide(
        offset: open ? Offset.zero : const Offset(0, 1.12),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: open ? 1 : 0,
          duration: Duration(milliseconds: open ? 200 : 260),
          curve: Curves.easeOut,
          child: _detailSheet(node),
        ),
      ),
    );
  }

  Widget _detailSheet(KnowledgeNode node) {
    final accent = knowledgeNodeColor(node);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.canvasCore.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.75),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          if (node.description != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              node.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.62),
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      color: Colors.white70,
                      tooltip: '关闭',
                      onPressed: () => setState(() => _selectedNode = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _glassPill('第 ${node.level + 1} 级'),
                    if (node.source == 'dify') _glassPill('AI 扩展'),
                    const SizedBox(width: 4),
                    _glassAction(
                      icon: Icons.menu_book_outlined,
                      label: '错题本',
                      onTap: () => context.go('/wrong-question/list'),
                    ),
                    _glassAction(
                      icon: Icons.auto_awesome,
                      label: '问 AI',
                      onTap: () => context.go('/smart-qa'),
                    ),
                    _glassAction(
                      icon: Icons.account_tree,
                      label: '树状图',
                      onTap: () => context.push('/home/tree'),
                      accent: accent,
                      filled: true,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _weaknessMistakesSection(node),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 弱点视图图例条：白→红→黑，与节点着色同一套函数。
  Widget _buildHeatLegend() {
    final weakness = ref.watch(knowledgeWeaknessProvider).asData?.value;
    final hasData = weakness != null && !weakness.isEmpty;
    final muted = Colors.white.withValues(alpha: 0.62);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '弱点',
            style: TextStyle(
              color: muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
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
          Text(
            hasData ? '0 道 → 最弱' : '暂无错题数据',
            style: TextStyle(color: muted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  /// 当前知识点的关联错题列表：点击任意一条直接打开错题详情。
  Widget _weaknessMistakesSection(KnowledgeNode node) {
    final weakness = ref.watch(knowledgeWeaknessProvider).asData?.value;
    final mistakes =
        weakness?.mistakesByNodeId[node.id] ?? const <WrongQuestion>[];

    if (mistakes.isEmpty) {
      return Text(
        '该知识点暂无错题记录（弱点视图下可查看全局漏洞分布）',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 12,
        ),
      );
    }

    final ownCount = weakness?.ownById[node.id]?.length ?? 0;
    final inheritedCount = mistakes.length - ownCount;

    final shown = mistakes.take(4).toList();
    final more = mistakes.length - shown.length;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 230),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              text: '关联错题 ${mistakes.length} 道',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              children: [
                if (inheritedCount > 0)
                  TextSpan(
                    text: '（含继承 $inheritedCount 道）',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: shown.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Colors.white12),
              itemBuilder: (context, i) {
                final wq = shown[i];
                return InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WrongQuestionDetailPage(item: wq),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            wq.questionText
                                .replaceAll(RegExp(r'\s+'), ' ')
                                .trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _masteryChip(wq.mastery),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '还有 $more 道，去错题本查看全部',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 掌握度小胶囊：未掌握红 / 复习中橙 / 已掌握绿。
  Widget _masteryChip(int mastery) {
    final (label, color) = switch (mastery) {
      0 => ('未掌握', const Color(0xFFE5484D)),
      1 => ('复习中', const Color(0xFFF5A623)),
      _ => ('已掌握', const Color(0xFF34C759)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _glassPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _glassAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? accent,
    bool filled = false,
  }) {
    final base = accent ?? Colors.white;
    final fg = filled ? Colors.white : Colors.white.withValues(alpha: 0.85);
    return AppPressScale(
      pressedScale: 0.94,
      child: Material(
        color: filled
            ? base.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSearchDialog() async {
    final picked = await showSearch<KnowledgeNode?>(
      context: context,
      delegate: _KnowledgeSearchDelegate(ref),
    );
    if (picked == null || !mounted) return;

    final graph = ref.read(graphDataProvider(_subjectFilter)).asData?.value;
    if (graph == null) return;

    // 搜索即入口：先展开路径让它可见，再把视角转过去。
    await _revealNode(picked, graph);
  }
}

/// Search delegate for knowledge nodes.
class _KnowledgeSearchDelegate extends SearchDelegate<KnowledgeNode?> {
  final WidgetRef ref;
  _KnowledgeSearchDelegate(this.ref);

  @override
  String get searchFieldLabel => '搜索知识点...';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildResults(query);

  @override
  Widget buildSuggestions(BuildContext context) => _buildResults(query);

  Widget _buildResults(String q) {
    if (q.length < 2) return const SizedBox.shrink();
    final ds = ref.read(knowledgeDataSourceProvider);
    return FutureBuilder<List<KnowledgeNode>>(
      future: Future.value(ds.search(q)),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LoadingIndicator();
        final results = snapshot.data!;
        if (results.isEmpty) {
          return const Center(child: Text('未找到相关知识点'));
        }
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (_, i) {
            final node = results[i];
            return ListTile(
              title: Text(node.title),
              subtitle: node.description != null
                  ? Text(node.description!)
                  : null,
              leading: Icon(
                Icons.circle,
                size: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
              onTap: () => close(context, node),
            );
          },
        );
      },
    );
  }
}