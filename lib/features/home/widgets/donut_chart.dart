import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/app_motion.dart';

/// 甜甜圈数据图的一段。
class DonutSlice {
  const DonutSlice({
    required this.value,
    required this.color,
    required this.label,
  });

  final num value;
  final Color color;
  final String label;
}

/// 甜甜圈式数据图：底环 + 分段彩环，中心显示总量。
///
/// 展开动画走 [AppMotion.pop]，环会先冲过目标角度再收回，和整站的 Q 弹手感一致。
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
    this.size = 112,
    this.strokeWidth = 14,
  });

  final List<DonutSlice> slices;
  final num centerValue;
  final String centerLabel;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.counter);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: AppMotion.pop,
      builder: (context, progress, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DonutPainter(
            progress: progress,
            slices: slices,
            strokeWidth: strokeWidth,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppCountUp(
                  value: centerValue,
                  duration: duration,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1D1D1F),
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  centerLabel,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF6E6E73),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.progress,
    required this.slices,
    required this.strokeWidth,
  });

  final double progress;
  final List<DonutSlice> slices;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    // 底环：数据为 0 时也能看到环的轮廓
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = const Color(0xFFE9EDF5),
    );

    final total = slices.fold<double>(0, (sum, s) => sum + s.value.toDouble());
    if (total <= 0) return;

    const gap = 0.05; // 每段之间留一道缝，直角风格下更利落
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = (slice.value / total) * 2 * math.pi * progress;
      if (sweep <= 0) continue;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        math.max(sweep - gap, 0.002),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt
          ..color = slice.color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.slices != slices;
}
