import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/motion/app_motion.dart';

/// 可展开的堆叠卡片（参考 `10.堆叠卡片动画` 的实现思路）。
///
/// 收起时所有卡片用「位移 + 缩小」叠在同一处，只露出每张的一条边；
/// 点「展开」后位移与缩放归零，卡片带过冲缓动弹开成竖排列表。
///
/// 原版是给每张卡设置 `translateY(n×自身高度) + scale` 并靠 CSS transition
/// 归零，这里用同一个思路：位移量按卡片高度直接换算，动画进度统一走 [t]。
class ExpandableStack extends StatefulWidget {
  const ExpandableStack({
    super.key,
    required this.itemCount,
    required this.cardBuilder,
    required this.cardHeight,
    this.gap = 12,
    this.peek = 16,
    this.collapsedLabel = '展开',
    this.expandedLabel = '收起',
    this.onCardTap,
    this.initiallyExpanded = false,
  });

  final int itemCount;

  /// 构建第 [index] 张卡片；[isFront] 表示它正处在最外层。
  final Widget Function(BuildContext context, int index, bool isFront)
  cardBuilder;

  final double cardHeight;

  /// 展开后卡片之间的间距。
  final double gap;

  /// 收起时每张卡露出的高度。
  final double peek;

  final String collapsedLabel;
  final String expandedLabel;
  final void Function(int index)? onCardTap;
  final bool initiallyExpanded;

  @override
  State<ExpandableStack> createState() => _ExpandableStackState();
}

class _ExpandableStackState extends State<ExpandableStack> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final n = widget.itemCount;
    if (n == 0) return const SizedBox.shrink();

    final h = widget.cardHeight;
    final collapsedHeight = h + (n - 1) * widget.peek;
    final expandedHeight = n * h + (n - 1) * widget.gap;
    final duration = AppMotion.resolve(
      context,
      const Duration(milliseconds: 460),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _expanded ? 1 : 0),
          duration: duration,
          // 原版用的是带回弹的 cubic-bezier(.68,-.55,.27,.03)，这里用同一手感的 bouncy
          curve: AppMotion.bouncy,
          builder: (context, t, _) {
            final height =
                lerpDouble(collapsedHeight, expandedHeight, t) ??
                collapsedHeight;

            return SizedBox(
              height: height,
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 反向绘制：index 0 最后画，收起来时压在最上面
                    for (var i = n - 1; i >= 0; i--)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: lerpDouble(
                          i * widget.peek,
                          i * (h + widget.gap),
                          t,
                        ),
                        height: h,
                        child: Transform.scale(
                          // 越靠后的卡片越小，收起来时才露出层次
                          scale: lerpDouble(1 - 0.05 * (i + 1), 1, t) ?? 1,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (_expanded) {
                                widget.onCardTap?.call(i);
                              } else {
                                _toggle();
                              }
                            },
                            child: widget.cardBuilder(
                              context,
                              i,
                              !_expanded && i == 0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Center(
          child: AppPressScale(
            pressedScale: 0.9,
            child: TextButton(
              onPressed: _toggle,
              style: TextButton.styleFrom(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded ? widget.expandedLabel : widget.collapsedLabel,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6E6E73),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: duration,
                    curve: AppMotion.bouncy,
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: Color(0xFF6E6E73),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
