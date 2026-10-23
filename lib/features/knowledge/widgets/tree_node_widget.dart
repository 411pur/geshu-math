import 'dart:math';
import 'package:flutter/material.dart';
import '../../../domain/entities/knowledge_entity.dart';
import '../../../core/theme/app_colors.dart';

/// Recursively renders a knowledge tree node with collapsible children.
class TreeNodeWidget extends StatefulWidget {
  final TreeNode node;
  final int depth;

  const TreeNodeWidget({
    super.key,
    required this.node,
    this.depth = 0,
  });

  @override
  State<TreeNodeWidget> createState() => _TreeNodeWidgetState();
}

class _TreeNodeWidgetState extends State<TreeNodeWidget>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  late final AnimationController _controller;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: _expanded ? 0.5 : 0.0,
    );
    _rotation = Tween<double>(begin: -0.25, end: 0.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasChildren = widget.node.children.isNotEmpty;
    final indent = 24.0 * widget.depth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: indent),
          child: InkWell(
            onTap: hasChildren ? _toggle : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Expand/collapse chevron
                  if (hasChildren)
                    AnimatedBuilder(
                      animation: _rotation,
                      builder: (context, child) => Transform.rotate(
                        angle: _rotation.value * pi * 2,
                        child: child,
                      ),
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    const SizedBox(width: 20),

                  const SizedBox(width: 4),

                  // Subject colour dot
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _subjectColor(widget.node.title),
                      shape: BoxShape.circle,
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Title
                  Text(
                    widget.node.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Children (lazy rendered)
        if (_expanded && hasChildren)
          ...widget.node.children.map(
            (child) => TreeNodeWidget(
              node: child,
              depth: widget.depth + 1,
            ),
          ),
      ],
    );
  }

  Color _subjectColor(String title) {
    if (title.contains('概率') || title.contains('统计') || title.contains('计数')) {
      return AppColors.statistics;
    }
    if (title.contains('导数') || title.contains('微积分')) return AppColors.calculus;
    if (title.contains('几何') || title.contains('向量')) return AppColors.geometry;
    if (title.contains('函数') || title.contains('三角') || title.contains('数列')) {
      return AppColors.functions;
    }
    if (title.contains('代数') || title.contains('方程') || title.contains('不等式')) {
      return AppColors.algebra;
    }
    return AppColors.primary;
  }
}
