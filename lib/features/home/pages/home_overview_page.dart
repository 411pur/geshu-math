import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/wrong_question_entity.dart';
import '../../wrong_question/pages/wrong_question_detail_page.dart';
import '../../wrong_question/providers/wrong_question_providers.dart';
import '../providers/home_providers.dart';
import '../widgets/learning_overview_card.dart';
import '../widgets/orbit_carousel.dart';
import '../providers/student_provider.dart';
import '../providers/student_profile_provider.dart';

/// 首页环形轮播的卡片数据：App 的主要功能入口。
///
/// 8 张卡片正好每隔 45° 排一圈，正面的那张最大最亮，两侧依次变小变暗，
/// 形成参考视频里那种持续循环转动的效果。
const List<OrbitCardData> kOrbitTools = [
  OrbitCardData(
    title: '错题指导',
    subtitle: '拍照提问，AI 诊断错因',
    icon: Icons.quiz_rounded,
    color: Color(0xFF0A63F5),
    path: '/wrong-question/chat',
  ),
  OrbitCardData(
    title: '拍照识题',
    subtitle: '拍下题目，自动识别题干',
    icon: Icons.document_scanner_rounded,
    color: Color(0xFF4F46E5),
    path: '/scan',
  ),
  OrbitCardData(
    title: '考试分析',
    subtitle: '上传试卷，生成能力雷达',
    icon: Icons.assignment_rounded,
    color: Color(0xFF10B981),
    path: '/exam/analysis',
  ),
  OrbitCardData(
    title: '智能问答',
    subtitle: '随时追问，讲到你懂',
    icon: Icons.chat_bubble_rounded,
    color: Color(0xFF7C3AED),
    path: '/smart-qa',
  ),
  OrbitCardData(
    title: '知识图谱',
    subtitle: '初高中全模块知识网络',
    icon: Icons.account_tree_rounded,
    color: Color(0xFF06B6D4),
    path: '/home/graph',
  ),
  OrbitCardData(
    title: '错题本',
    subtitle: '按掌握度成组复习',
    icon: Icons.book_rounded,
    color: Color(0xFFE11D48),
    path: '/wrong-question/list',
  ),
  OrbitCardData(
    title: '考情历史',
    subtitle: '历次考试趋势一目了然',
    icon: Icons.timeline_rounded,
    color: Color(0xFFF59E0B),
    path: '/exam/history',
  ),
  OrbitCardData(
    title: '学习报告',
    subtitle: '一键生成阶段学习报告',
    icon: Icons.assessment_rounded,
    color: Color(0xFFFB7185),
    path: '/profile/report',
  ),
];

/// 首页概览（样品 A 布局）：渐变欢迎头 + 统计卡 + 学习工具入口 + 最近错题
class HomeOverviewPage extends ConsumerWidget {
  const HomeOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentId = ref.watch(studentIdProvider);
    final profile = ref.watch(studentProfileProvider);
    final statsAsync = ref.watch(homeStatsProvider);
    // 甜甜圈用真实分布：拉全量错题自己算，不再用占位比例
    final wrongAsync = ref.watch(
      wrongQuestionsProvider(const WrongQuestionFilter(limit: 500, offset: 0)),
    );
    final displayName = profile.name.isNotEmpty
        ? profile.name
        : (studentId.isNotEmpty ? studentId : '同学');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7F9FD), Color(0xFFEAEFF9)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              AppReveal(index: 0, child: _buildGreeting(context, displayName)),
              AppReveal(
                index: 1,
                child: _buildBoard(context, statsAsync, wrongAsync),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── 顶部问候（一行字即可；头像已在顶部工具栏，这里不重复显示）──
  Widget _buildGreeting(BuildContext context, String name) {
    final now = DateTime.now();
    final salute = now.hour < 6
        ? '夜深了'
        : now.hour < 12
        ? '早上好'
        : now.hour < 18
        ? '下午好'
        : '晚上好';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Row(
        children: [
          Container(width: 4, height: 22, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$salute，$name · ${now.month}月${now.day}日',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 19,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 学习情况 + 学习工具：同一块面板 ───────────────────
  Widget _buildBoard(
    BuildContext context,
    AsyncValue<HomeStats> statsAsync,
    AsyncValue<List<WrongQuestion>> wrongAsync,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
        decoration: _boardSurface(),
        child: AppStateSwitcher(
          alignment: Alignment.centerLeft,
          child: statsAsync.when(
            loading: () => const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, _) => _toolSection(context),
            data: (stats) {
              final all = wrongAsync.asData?.value ?? const <WrongQuestion>[];
              final sorted = [...all]
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              final mastered = all.where((w) => w.mastery == 2).length;
              final reviewing = all.where((w) => w.mastery == 1).length;
              final untouched = (all.length - mastered - reviewing).clamp(
                0,
                all.length,
              );
              final weekAgo =
                  DateTime.now().millisecondsSinceEpoch - 7 * 86400000;
              final newThisWeek = all
                  .where((w) => w.createdAt >= weekAgo)
                  .length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 试验版：学习工具在上、学习情况在下
                  _toolSection(context),
                  const SizedBox(height: 22),
                  Container(height: 1, color: const Color(0x140F172A)),
                  const SizedBox(height: 18),
                  LearningOverviewCard(
                    embedded: true,
                    total: all.length,
                    mastered: mastered,
                    reviewing: reviewing,
                    untouched: untouched,
                    newThisWeek: newThisWeek,
                    examCount: stats.examCount,
                    averageScore: stats.averageScore,
                    weakPoints: _weakPoints(all),
                    questions: sorted,
                    onOpenQuestion: (item) => _openWrongQuestion(context, item),
                    onViewAll: () => context.go('/wrong-question/list'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 面板下半部分：学习工具。标题与顶部问候用同一条蓝色直角竖条统一。
  Widget _toolSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 4, height: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text(
              '学习工具',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            // 手机窄屏（可用宽 < 520）：改用两列宫格，避免 3D 环形轮播
            // 在窄容器里被裁切、且悬停交互在触摸设备上无意义。
            if (constraints.maxWidth < 520) {
              return _ToolGrid(
                items: kOrbitTools,
                onOpen: (index) => context.go(kOrbitTools[index].path),
              );
            }
            return OrbitCarousel(
              items: kOrbitTools,
              onOpen: (index) => context.go(kOrbitTools[index].path),
              cardWidth: 210,
              cardHeight: 286,
              radius: 292,
              height: 356,
            );
          },
        ),
      ],
    );
  }

  BoxDecoration _boardSurface() => const BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.zero,
    border: Border.fromBorderSide(BorderSide(color: Color(0x140F172A))),
    boxShadow: [
      BoxShadow(color: Color(0x0F0F172A), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x140F172A),
        blurRadius: 24,
        offset: Offset(0, 10),
        spreadRadius: -12,
      ),
    ],
  );

  /// 从 topic / tags 聚合出最薄弱的三个知识点。
  List<String> _weakPoints(List<WrongQuestion> all) {
    final counter = <String, int>{};
    for (final item in all) {
      final topic = (item.topic ?? '').trim();
      if (topic.isNotEmpty) counter[topic] = (counter[topic] ?? 0) + 1;

      final tags = item.tagsJson;
      if (tags == null || tags.isEmpty) continue;
      try {
        for (final tag in json.decode(tags) as List<dynamic>) {
          final text = tag.toString().trim();
          if (text.isNotEmpty) counter[text] = (counter[text] ?? 0) + 1;
        }
      } catch (_) {
        // 标签不是合法 JSON 时忽略，不影响页面
      }
    }
    final sorted = counter.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).map((e) => '${e.key} ×${e.value}').toList();
  }

  /// 展开状态下点某张卡：进入这道错题的详情页。
  void _openWrongQuestion(BuildContext context, WrongQuestion item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WrongQuestionDetailPage(item: item)),
    );
  }
}

/// 手机窄屏「学习工具」两列宫格：替代 3D 环形轮播。
///
/// 触摸设备没有悬停，环形轮播的抽牌/暂停交互无从触发；且窄容器下
/// 半径与卡片宽度互相挤压导致裁切。宫格让 8 个入口一屏可见、点即进入。
class _ToolGrid extends StatelessWidget {
  const _ToolGrid({required this.items, required this.onOpen});

  final List<OrbitCardData> items;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.5,
      ),
      itemBuilder: (context, index) => _ToolTile(
        data: items[index],
        onTap: () => onOpen(index),
      ),
    );
  }
}

/// 宫格里的单个功能入口：与环形卡片同一套配色/直角语言。
class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.data, required this.onTap});

  final OrbitCardData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: data.color,
      borderRadius: BorderRadius.zero,
      clipBehavior: Clip.hardEdge,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(data.color, Colors.white, 0.06)!,
              data.color,
              Color.lerp(data.color, const Color(0xFF05070E), 0.42)!,
            ],
            stops: const [0, 0.5, 1],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.40),
                    ),
                  ),
                  child: Icon(data.icon, color: Colors.white, size: 20),
                ),
                const Spacer(),
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 11,
                    height: 1.3,
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
