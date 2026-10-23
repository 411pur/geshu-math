import 'package:flutter/material.dart';

/// 格数至理配色（Apple HIG 风格）
///
/// 遵循 iOS 人机交互指南：分组灰底、系统蓝、轻分割线、近黑文字。
class AppColors {
  AppColors._();

  // ── iOS System Colors ─────────────────────────────────
  static const Color primary = Color(0xFF007AFF); // iOS System Blue
  static const Color accent = Color(0xFF34C759); // iOS System Green
  static const Color background = Color(0xFFF5F6FA); // 工作台浅蓝灰底（毛玻璃卡片衬底）
  static const Color surface = Color(0xFFFFFFFF); // 卡片白
  static const Color secondarySystem = Color(0xFFF2F2F7); // 次级背景
  static const Color foreground = Color(0xFF1D1D1F); // 近黑主文字
  static const Color mutedForeground = Color(0xFF6E6E73); // 次级文字
  static const Color border = Color(0xFFE5E5EA); // iOS Separator
  static const Color error = Color(0xFFFF3B30); // iOS System Red
  static const Color warning = Color(0xFFFF9500); // iOS System Orange

  // ── 数学模块分类色（知识图谱与错题标签共用，iOS 柔和系）───
  static const Color algebra = Color(0xFF007AFF); // 数与代数、方程与不等式 – 蓝
  static const Color functions = Color(0xFFF59E0B); // 函数、三角函数、数列 – 橙
  static const Color geometry = Color(0xFF06B6D4); // 平面/立体/解析几何、向量 – 青
  static const Color statistics = Color(0xFFFF3B30); // 计数原理、概率与统计 – 红
  static const Color calculus = Color(0xFF34C759); // 导数与微积分 – 绿

  // ── 知识图谱画布（深色，用于突出立体纵深）─────────────
  /// 画布中心色（略微提亮，制造球体受光感）。
  static const Color canvasCore = Color(0xFF121A2B);

  /// 画布边缘色（压暗，配合暗角）。
  static const Color canvasEdge = Color(0xFF070A12);

  /// 平面（2D）模式画布底色。
  static const Color canvasBase = Color(0xFF0C1220);

  /// 球壳轨道参考线。
  static const Color orbit = Color(0xFF5B7BA8);

  /// Look up the colour for a maths module category.
  ///
  /// 同时接受中文模块名与知识图谱里的模块 id，方便错题标签与图谱共用。
  static Color forSubject(String subject) {
    final s = subject.trim();
    if (s.isEmpty) return primary;
    if (s.contains('概率') || s.contains('统计') || s.contains('计数')) {
      return statistics;
    }
    if (s.contains('导数') || s.contains('微积分')) return calculus;
    if (s.contains('几何') || s.contains('向量')) return geometry;
    if (s.contains('函数') || s.contains('三角') || s.contains('数列')) {
      return functions;
    }
    if (s.contains('代数') || s.contains('方程') || s.contains('不等式')) {
      return algebra;
    }
    switch (s) {
      case 'number-and-algebra':
      case 'equation-inequality':
      case 'set-function-derivative':
        return algebra;
      case 'trigonometry':
      case 'sequence':
        return functions;
      case 'plane-geometry':
      case 'solid-geometry':
      case 'analytic-geometry':
      case 'vector-complex':
        return geometry;
      case 'counting-probability-stats':
        return statistics;
      default:
        return primary;
    }
  }
}