import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/knowledge_entity.dart';

/// 三维坐标点。
///
/// 刻意不引入 vector_math / 任何三方依赖 —— 这里只用得到最基础的三维向量
/// 加减与缩放，自己写 20 行比多一个依赖划算。
class V3 {
  final double x;
  final double y;
  final double z;
  const V3(this.x, this.y, this.z);

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);
}

/// 单个节点投影到屏幕后的命中信息。
///
/// 页面用它在画布坐标系里做点击/悬停命中，并用 [world] 计算"旋转到该节点"
/// 的目标视角。
class NodeHit {
  /// 画布坐标（未经 InteractiveViewer 变换）。
  final Offset position;

  /// 距相机的距离，越小越靠前。
  final double depth;

  /// 该节点在屏幕上的半径（已含透视缩放）。
  final double radius;

  /// 该节点的世界坐标，供页面计算目标 yaw / pitch。
  final V3 world;

  const NodeHit(this.position, this.depth, this.radius, this.world);
}

/// 已排好位置、等待绘制的一条标签。
class _PlacedLabel {
  final TextPainter painter;
  final Offset origin;
  final Rect bounds;
  final RRect background;
  final double alpha;
  const _PlacedLabel({
    required this.painter,
    required this.origin,
    required this.bounds,
    required this.background,
    required this.alpha,
  });
}

/// 相机空间下的一个点。
class _View {
  final double x;
  final double y;
  final double z;
  const _View(this.x, this.y, this.z);
}

/// 知识图谱绘制器：透视投影的立体同心球壳。
///
/// 布局思路 —— 保留"层级 = 离心距离"这一既有语义，但把每一层从
/// 平面圆环升级成球壳，并按 L0 科目把球面切成扇区，让同一科目的
/// 章节聚在一起：
///
/// * L0（数与代数/函数/几何…）落在最小球壳的赤道上，每个模块占一个扇区中心；
/// * L1（章）落在同一扇区的中层球壳，铺满该扇区的上下范围；
/// * L2（节）落在同一扇区的外层球壳。
///
/// 渲染思路 —— 相机绕原点做 yaw / pitch 旋转 + 透视除法，
/// 再用画家算法（远的先画）排序，配合深度衰减、球体光照、
/// 落地阴影和轨道参考线制造纵深。
class KnowledgeGraphPainter extends CustomPainter {
  final GraphData graphData;
  final String? selectedNodeId;

  /// 悬停节点（比 selected 优先级更高，用于"临时探照"）。
  final String? hoveredNodeId;

  /// 最大展开层级：只绘制 level <= maxLevel 的节点。
  final int maxLevel;

  /// 已手动展开的节点 id（点击节点展开其子级）。
  final Set<String> expandedIds;

  /// 是否使用立体（球壳）布局；关闭时回到平面同心环。
  final bool use3D;

  /// 水平旋转角（弧度）。
  final double yaw;

  /// 俯仰角（弧度）。
  final double pitch;

  /// 当前 InteractiveViewer 的缩放，用于标签 LOD。
  final double viewScale;

  /// 每帧回填 (id -> 屏幕命中信息)，供页面做命中测试与旋转定位。
  final void Function(Map<String, NodeHit> hits)? positionsCallback;

  // ── 相机 ────────────────────────────────────────────────
  static const double _camDist = 1700.0;
  static const double _focal = 1550.0;
  static const double _minViewZ = 140.0;

  // ── 平面（2D）布局：与旧版一致，保证关掉 3D 后语义不变 ──
  static const double _flatBase = 60.0;
  static const double _flatRing = 100.0;

  // ── 立体（3D）布局：每层一个球壳 ────────────────────────
  static const List<double> _shellRadius = [58, 158, 250, 330];

  /// 每层的极角带（度，0 = 正上方，90 = 赤道）。
  static const List<List<double>> _shellPolarDeg = [
    [74, 106],
    [46, 134],
    [20, 160],
    [10, 170],
  ];

  KnowledgeGraphPainter({
    required this.graphData,
    this.selectedNodeId,
    this.hoveredNodeId,
    this.maxLevel = 2,
    this.expandedIds = const {},
    this.use3D = true,
    this.yaw = 0,
    this.pitch = 0.16,
    this.viewScale = 1,
    this.positionsCallback,
  });

  /// 当前布局下所有节点的 id -> 节点。
  Map<String, KnowledgeNode> _byId = const {};

  /// 每帧算一次的全局适配缩放（见 [_computeFit]）。
  double _fit = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (graphData.nodes.isEmpty) return;
    _byId = {for (final n in graphData.nodes) n.id: n};
    _fit = _computeFit(size);

    // ── 1. 布局 ───────────────────────────────────────────
    final world = _computeLayout();
    if (world.isEmpty) return;

    // ── 2. 投影 ───────────────────────────────────────────
    final hits = <String, NodeHit>{};
    for (final entry in world.entries) {
      final node = _byId[entry.key];
      if (node == null) continue;
      hits[entry.key] = _project(node, entry.value, size);
    }
    positionsCallback?.call(hits);

    // 画家算法：depth 大的（更远）先画
    final ordered = hits.entries.toList()
      ..sort((a, b) => b.value.depth.compareTo(a.value.depth));

    final focusId = hoveredNodeId ?? selectedNodeId;
    final focusSet = _focusSet(focusId);

    // ── 3. 绘制 ───────────────────────────────────────────
    _drawBackground(canvas, size);
    _drawOrbitRings(canvas, size);
    _drawEdges(canvas, size, hits, focusSet);
    for (final e in ordered) {
      final node = _byId[e.key];
      if (node != null) _drawNode(canvas, node, e.value, focusId, focusSet);
    }
    _drawLabels(canvas, ordered, size, focusId, focusSet);
  }

  @override
  bool shouldRepaint(covariant KnowledgeGraphPainter oldDelegate) =>
      graphData != oldDelegate.graphData ||
      selectedNodeId != oldDelegate.selectedNodeId ||
      hoveredNodeId != oldDelegate.hoveredNodeId ||
      maxLevel != oldDelegate.maxLevel ||
      expandedIds != oldDelegate.expandedIds ||
      use3D != oldDelegate.use3D ||
      yaw != oldDelegate.yaw ||
      pitch != oldDelegate.pitch ||
      viewScale != oldDelegate.viewScale;

  // ── 可见性 ──────────────────────────────────────────────

  bool _isVisible(KnowledgeNode node) {
    if (node.level <= 1) return true;
    if (node.level > maxLevel) return false;
    return _isAncestorExpanded(node);
  }

  bool _isAncestorExpanded(KnowledgeNode node) {
    KnowledgeNode? cur = node;
    var guard = 0;
    while (cur != null && cur.level > 1 && guard++ < 16) {
      final pid = cur.parentId;
      if (pid == null) break;
      final parent = _byId[pid];
      if (parent == null) return true;
      if (parent.level >= maxLevel && !expandedIds.contains(parent.id)) {
        return false;
      }
      cur = parent;
    }
    return true;
  }

  // ── 布局 ────────────────────────────────────────────────

  Map<String, V3> _computeLayout() {
    final visible = graphData.nodes.where(_isVisible).toList();
    final out = <String, V3>{};
    if (visible.isEmpty) return out;

    if (!use3D) {
      // 平面同心环：每层一个圆，节点等分。
      final byLevel = <int, List<KnowledgeNode>>{};
      for (final n in visible) {
        byLevel.putIfAbsent(n.level, () => []).add(n);
      }
      for (final entry in byLevel.entries) {
        final radius = _flatBase + entry.key * _flatRing;
        final list = entry.value;
        for (var i = 0; i < list.length; i++) {
          final a = (2 * pi * i / list.length) - pi / 2;
          out[list[i].id] = V3(radius * cos(a), radius * sin(a), 0);
        }
      }
      return out;
    }

    // 立体：按最顶层祖先（科目）划分方位角扇区。
    final roots = <String>[];
    for (final n in visible) {
      final r = _rootIdOf(n);
      if (!roots.contains(r)) roots.add(r);
    }
    if (roots.isEmpty) return out;

    final span = 2 * pi / roots.length;
    final half = span * 0.42; // 扇区之间留缝，视觉上分得开
    final sector = <String, List<double>>{};
    for (var i = 0; i < roots.length; i++) {
      final center = -pi / 2 + i * span;
      sector[roots[i]] = [center - half, center + half];
    }

    // 按 (层级, 科目) 分组，再在各自扇区内铺开。
    final groups = <int, Map<String, List<KnowledgeNode>>>{};
    for (final n in visible) {
      final lvl = n.level.clamp(0, _shellRadius.length - 1);
      final root = _rootIdOf(n);
      groups.putIfAbsent(lvl, () => {}).putIfAbsent(root, () => []).add(n);
    }

    for (final lvlEntry in groups.entries) {
      final lvl = lvlEntry.key;
      final radius = _shellRadius[lvl];
      final band = _shellPolarDeg[lvl];
      final p0 = band[0] * pi / 180;
      final p1 = band[1] * pi / 180;
      for (final g in lvlEntry.value.entries) {
        final s = sector[g.key];
        if (s == null) continue;
        _placeOnShell(g.value, s[0], s[1], p0, p1, radius, out);
      }
    }
    return out;
  }

  /// 沿父链上溯到最顶层祖先的 id。
  String _rootIdOf(KnowledgeNode node) {
    var cur = node;
    var guard = 0;
    while (cur.parentId != null && guard++ < 16) {
      final parent = _byId[cur.parentId];
      if (parent == null) break;
      cur = parent;
    }
    return cur.id;
  }

  /// 把一个扇区内的兄弟节点铺到球面上。
  ///
  /// 用错列的网格而不是单圈等分：单圈会让 40 个节点挤在同一条弧上
  /// （这正是旧版最外圈糊成一团的根因），铺成面之后格子面积足够，
  /// 标签和节点都不会重叠。
  void _placeOnShell(
    List<KnowledgeNode> nodes,
    double az0,
    double az1,
    double p0,
    double p1,
    double radius,
    Map<String, V3> out,
  ) {
    final n = nodes.length;
    if (n == 0) return;

    final azSpan = az1 - az0;
    final pSpan = p1 - p0;

    // 按该扇区水平弧长 / 垂直弧长的比例决定列数，让格子尽量接近正方形。
    final midPolar = (p0 + p1) / 2;
    final arcAz = azSpan * radius * sin(midPolar);
    final arcP = pSpan * radius;
    var cols = sqrt(n * (arcAz / max(arcP, 1.0))).round();
    cols = cols.clamp(1, n).toInt();
    final rows = (n / cols).ceil();

    for (var k = 0; k < n; k++) {
      final row = k ~/ cols;
      final col = k % cols;
      final stagger = row.isOdd ? 0.5 : 0.0;
      final azT = ((col + 0.5 + stagger) / cols).clamp(0.0, 1.0).toDouble();
      final pT = rows == 1 ? 0.5 : (row + 0.5) / rows;
      out[nodes[k].id] = _spherical(
        radius,
        az0 + azSpan * azT,
        p0 + pSpan * pT,
      );
    }
  }

  /// 球坐标 -> 世界坐标（极角自 +Y 轴量起，与画布 y 向下一致）。
  V3 _spherical(double r, double az, double polar) {
    final sp = sin(polar);
    return V3(r * sp * cos(az), r * cos(polar), r * sp * sin(az));
  }

  // ── 投影 ────────────────────────────────────────────────

  /// 世界坐标 -> 相机空间：先绕 Y 轴 yaw，再绕 X 轴 pitch。
  _View _toView(V3 p) {
    final cy = cos(yaw);
    final sy = sin(yaw);
    final x1 = p.x * cy - p.z * sy;
    final z1 = p.x * sy + p.z * cy;

    final cp = cos(pitch);
    final sp = sin(pitch);
    final y2 = p.y * cp - z1 * sp;
    final z2 = p.y * sp + z1 * cp;

    return _View(x1, y2, max(z2 + _camDist, _minViewZ));
  }

  /// 自适应缩放：让"当前可见的最外层球壳"刚好占满可视短边的约 0.42，
  /// 这样平面 / 立体、宽屏 / 竖屏下都有稳定的构图，也不会被裁掉。
  /// 每帧只在 paint 里算一次，避免逐节点重复扫描。
  double _computeFit(Size size) {
    var maxR = use3D ? _shellRadius[0] : _flatBase;
    for (final n in graphData.nodes) {
      if (!_isVisible(n)) continue;
      final r = use3D
          ? _shellRadius[n.level.clamp(0, _shellRadius.length - 1)]
          : _flatBase + n.level * _flatRing;
      if (r > maxR) maxR = r;
    }
    // 近端节点会被透视放大到 focal / (camDist - maxR)，按它留边距，
    // 这样转到任何角度外圈都不会被裁掉。
    final target = min(size.width, size.height) * 0.46;
    final nearPersp = _focal / max(_camDist - maxR, 1.0);
    return (target / (maxR * nearPersp)).clamp(0.4, 2.0).toDouble();
  }

  Offset _screen(_View v, Size size) {
    final persp = _focal / v.z * _fit;
    return Offset(size.width / 2 + v.x * persp, size.height / 2 + v.y * persp);
  }

  NodeHit _project(KnowledgeNode node, V3 world, Size size) {
    final v = _toView(world);
    final persp = _focal / v.z * _fit;
    final radius = _baseRadius(node.level) * persp * (use3D ? 1.0 : 0.85);
    return NodeHit(_screen(v, size), v.z, radius, world);
  }

  /// 节点世界半径（屏幕半径 = 它 × 透视系数）。
  double _baseRadius(int level) {
    switch (level) {
      case 0:
        return 17.0;
      case 1:
        return 11.0;
      case 2:
        return 7.0;
      default:
        return 5.0;
    }
  }

  /// 深度归一化：0 = 最近，1 = 最远。
  double _depthT(double viewZ) {
    const r = 300.0;
    const lo = _camDist - r;
    const hi = _camDist + r;
    return ((viewZ - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble();
  }

  // ── 焦点集合 ────────────────────────────────────────────

  /// 焦点节点 + 一跳邻居。空集合表示"没有焦点，全部正常显示"。
  Set<String> _focusSet(String? focusId) {
    if (focusId == null) return const {};
    final s = <String>{focusId};
    for (final e in graphData.edges) {
      if (e.fromId == focusId) s.add(e.toId);
      if (e.toId == focusId) s.add(e.fromId);
    }
    return s;
  }

  // ── 绘制 ────────────────────────────────────────────────

  void _drawBackground(Canvas canvas, Size size) {
    // 只画一层中心辉光，四周完全透明。背景渐变交给页面容器统一处理，
    // 这样画布和顶部工具条之间不可能出现接缝。
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.72,
          colors: [
            AppColors.canvasCore.withValues(alpha: 0.90),
            AppColors.canvasCore.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(rect),
    );
  }

  /// 每层球壳的赤道轨道线：透视后会变成椭圆，是最省算力的纵深线索。
  void _drawOrbitRings(Canvas canvas, Size size) {
    if (!use3D) return;
    final levels = <int>{};
    for (final n in graphData.nodes) {
      if (_isVisible(n)) levels.add(n.level.clamp(0, _shellRadius.length - 1));
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.orbit.withValues(alpha: 0.30);

    for (final lvl in levels) {
      final r = _shellRadius[lvl];
      final path = Path();
      const steps = 84;
      for (var i = 0; i <= steps; i++) {
        final a = 2 * pi * i / steps;
        final pt = _screen(_toView(V3(r * cos(a), 0, r * sin(a))), size);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawEdges(
    Canvas canvas,
    Size size,
    Map<String, NodeHit> hits,
    Set<String> focusSet,
  ) {
    final center = Offset(size.width / 2, size.height / 2);
    // 远的边先画，近的边后画，避免近处细线被远处盖住。
    final edges = graphData.edges.toList()
      ..sort((a, b) {
        final da = (hits[a.fromId]?.depth ?? 0) + (hits[a.toId]?.depth ?? 0);
        final db = (hits[b.fromId]?.depth ?? 0) + (hits[b.toId]?.depth ?? 0);
        return db.compareTo(da);
      });

    for (final edge in edges) {
      final a = hits[edge.fromId];
      final b = hits[edge.toId];
      if (a == null || b == null) continue;

      final parent = _byId[edge.fromId];
      final base = parent == null ? AppColors.primary : _colorForNode(parent);
      final hot = focusSet.isNotEmpty &&
          focusSet.contains(edge.fromId) &&
          focusSet.contains(edge.toId);

      final t = _depthT((a.depth + b.depth) / 2);
      final alpha = ((hot ? 0.85 : 0.26) * (1 - 0.55 * t)).clamp(0.0, 1.0).toDouble();

      final mid = Offset(
        (a.position.dx + b.position.dx) / 2,
        (a.position.dy + b.position.dy) / 2,
      );
      var outward = mid - center;
      if (outward.distance < 1) outward = const Offset(0, 1);
      final ctrl = mid + outward / outward.distance * 10;

      final path = Path()
        ..moveTo(a.position.dx, a.position.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, b.position.dx, b.position.dy);

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = hot ? 1.8 : 1.0
          ..color = base.withValues(alpha: alpha),
      );
    }
  }

  void _drawNode(
    Canvas canvas,
    KnowledgeNode node,
    NodeHit hit,
    String? focusId,
    Set<String> focusSet,
  ) {
    final r = hit.radius;
    if (r < 0.6) return;

    var alpha = 1 - 0.5 * _depthT(hit.depth);
    if (focusId != null && !focusSet.contains(node.id)) alpha *= 0.16;
    alpha = alpha.clamp(0.0, 1.0).toDouble();

    final color = _colorForNode(node);
    final isSelected = node.id == selectedNodeId;
    final isHovered = node.id == hoveredNodeId;

    // 落地阴影：给球体一个"站在空间里"的锚点。
    if (r >= 4) {
      final sr = Rect.fromCenter(
        center: hit.position + Offset(r * 0.18, r * 1.0),
        width: r * 2.1,
        height: r * 0.9,
      );
      canvas.drawOval(
        sr,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.black.withValues(alpha: 0.42 * alpha),
              Colors.black.withValues(alpha: 0.0),
            ],
          ).createShader(sr),
      );
    }

    if (r >= 3) {
      // 球体：左上受光的径向渐变
      final rect = Rect.fromCircle(center: hit.position, radius: r);
      canvas.drawCircle(
        hit.position,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.38, -0.42),
            radius: 1.05,
            colors: [
              Color.lerp(color, Colors.white, 0.55)!,
              color,
              Color.lerp(color, Colors.black, 0.45)!,
            ],
            stops: const [0.0, 0.52, 1.0],
          ).createShader(rect),
      );
      // 边缘轮廓光
      canvas.drawCircle(
        hit.position,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.6, r * 0.10)
          ..color = Colors.white.withValues(alpha: 0.20 * alpha),
      );
      // 高光点
      canvas.drawCircle(
        hit.position + Offset(-r * 0.34, -r * 0.38),
        max(0.8, r * 0.20),
        Paint()..color = Colors.white.withValues(alpha: 0.55 * alpha),
      );
    } else {
      canvas.drawCircle(
        hit.position,
        max(r, 1.2),
        Paint()..color = color.withValues(alpha: alpha),
      );
    }

    if (isSelected || isHovered) {
      canvas.drawCircle(
        hit.position,
        r + 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        hit.position,
        r + 11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = color.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  // ── 标签（LOD + 碰撞剔除）───────────────────────────────

  static final RegExp _chapterPrefix =
      RegExp(r'^第[一二三四五六七八九十百千零〇\d]+\s*[章节部分]\s*');

  /// 去掉"第七章 "这类前缀 —— 标签太长是默认视图互相压字的主因。
  String _labelText(KnowledgeNode node) {
    final stripped = node.title.replaceFirst(_chapterPrefix, '').trim();
    return stripped.isEmpty ? node.title : stripped;
  }

  /// 谁有资格显示标签。
  bool _labelAllowed(
    KnowledgeNode node,
    String? focusId,
    Set<String> focusSet,
    bool forced,
  ) {
    if (forced) return true;
    if (focusId != null) return focusSet.contains(node.id);
    if (node.level <= 1) return true;
    return viewScale >= 1.25 && node.level == 2;
  }

  /// 先按"近 -> 远"决定谁占位（近的优先），再按"远 -> 近"绘制。
  void _drawLabels(
    Canvas canvas,
    List<MapEntry<String, NodeHit>> ordered,
    Size size,
    String? focusId,
    Set<String> focusSet,
  ) {
    final placed = <Rect>[];
    final chosen = <_PlacedLabel>[];

    for (final e in ordered.reversed) {
      final node = _byId[e.key];
      if (node == null) continue;
      final hit = e.value;
      // 只有被直接选中 / 悬停的节点强制显示；邻居也要参与碰撞剔除，
      // 否则一悬停就同时抖出一堆互相压住的标签。
      final forced =
          node.id == selectedNodeId || node.id == hoveredNodeId;

      if (!_labelAllowed(node, focusId, focusSet, forced)) continue;

      final label = _buildLabel(node, hit, size, focusId, focusSet);
      if (label == null) continue;

      if (!forced && placed.any((r) => r.overlaps(label.bounds))) continue;

      placed.add(label.bounds);
      chosen.add(label);
    }

    for (final label in chosen.reversed) {
      canvas.drawRRect(
        label.background,
        Paint()..color = Colors.black.withValues(alpha: 0.42 * label.alpha),
      );
      label.painter.paint(canvas, label.origin);
    }
  }

  _PlacedLabel? _buildLabel(
    KnowledgeNode node,
    NodeHit hit,
    Size size,
    String? focusId,
    Set<String> focusSet,
  ) {
    final text = _labelText(node);
    if (text.isEmpty) return null;

    var alpha = 1 - 0.45 * _depthT(hit.depth);
    if (focusId != null && !focusSet.contains(node.id)) alpha *= 0.25;
    alpha = alpha.clamp(0.0, 1.0).toDouble();

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.95 * alpha),
          fontSize: node.level == 0 ? 12.5 : (node.level == 1 ? 11 : 10),
          fontWeight: node.level <= 1 ? FontWeight.w600 : FontWeight.w500,
          height: 1.15,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: node.level <= 1 ? 130 : 96);

    // 沿"离圆心向外"的方向摆，避免所有标签都向右堆成一片。
    final center = Offset(size.width / 2, size.height / 2);
    var dir = hit.position - center;
    if (dir.distance < 1) dir = const Offset(1, 0);
    final u = dir / dir.distance;

    const gap = 7.0;
    double x;
    double y;
    if (u.dx.abs() >= u.dy.abs()) {
      x = u.dx >= 0
          ? hit.position.dx + hit.radius + gap
          : hit.position.dx - hit.radius - gap - tp.width;
      y = hit.position.dy - tp.height / 2;
    } else {
      x = hit.position.dx - tp.width / 2;
      y = u.dy >= 0
          ? hit.position.dy + hit.radius + gap
          : hit.position.dy - hit.radius - gap - tp.height;
    }

    final maxX = max(4.0, size.width - tp.width - 4);
    final maxY = max(4.0, size.height - tp.height - 4);
    x = x.clamp(4.0, maxX).toDouble();
    y = y.clamp(4.0, maxY).toDouble();

    final bounds = Rect.fromLTWH(x - 4, y - 3, tp.width + 8, tp.height + 6);
    return _PlacedLabel(
      painter: tp,
      origin: Offset(x, y),
      bounds: bounds,
      background: RRect.fromRectAndRadius(bounds, const Radius.circular(6)),
      alpha: alpha,
    );
  }


  /// 按标题关键字推断科目色（保持原有语义）。
  Color _colorForNode(KnowledgeNode node) => knowledgeNodeColor(node);
}

/// 按标题关键字推断数学模块色（painter 与详情面板共用，避免两处语义漂移）。
Color knowledgeNodeColor(KnowledgeNode node) =>
    knowledgeColorForTitle(node.title);

/// 标题 → 数学模块色。顺序敏感：先匹配更具体的模块。
Color knowledgeColorForTitle(String title) {
  bool has(List<String> words) => words.any(title.contains);

  if (has(['概率', '统计', '随机', '计数', '排列', '组合', '二项式'])) {
    return AppColors.statistics;
  }
  if (has(['导数', '微分', '积分', '极限'])) return AppColors.calculus;
  if (has(['几何', '三角形', '四边形', '圆', '相似', '全等', '平行', '垂直',
      '向量', '坐标', '直线', '椭圆', '双曲线', '抛物线', '立体', '空间',
      '棱柱', '棱锥', '球'])) {
    return AppColors.geometry;
  }
  if (has(['函数', '指数', '对数', '三角', '数列', '等差', '等比', '弧度',
      '正弦', '余弦', '正切'])) {
    return AppColors.functions;
  }
  if (has(['代数', '方程', '不等式', '实数', '有理数', '整式', '分式',
      '根式', '集合', '逻辑', '复数'])) {
    return AppColors.algebra;
  }
  return AppColors.primary;
}
