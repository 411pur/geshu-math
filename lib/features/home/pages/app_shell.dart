import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../report/services/report_scheduler.dart';
import '../../report/services/report_generator.dart';
import '../providers/student_provider.dart';
import '../providers/student_profile_provider.dart';

// ── Dark sidebar palette (hardcoded; does not modify app_theme) ──────────
class _SidebarPalette {
  static const Color bg = Color(0xFF1C1C1E);
  static const Color hover = Color(0xFF2C2C2E);
  static const Color activeBg = Color(0xFF0A84FF);
  static const Color activeText = Color(0xFFFFFFFF);
  static const Color inactiveText = Color(0xFF98989F);
  static const Color groupTitle = Color(0xFF636366);
  static const Color divider = Color(0xFF38383A);
  static const Color logoText = Color(0xFFFFFFFF);
  static const Color chipBg = Color(0xFF2C2C2E);
  static const Color chipText = Color(0xFF98989F);
}

// ── Nav data model ───────────────────────────────────────────────────────
class _NavItemData {
  final String label;
  final String path;
  final IconData icon;
  final IconData activeIcon;
  const _NavItemData(this.label, this.path, this.icon, this.activeIcon);
}

class _NavGroupData {
  final String title;
  final List<_NavItemData> items;
  const _NavGroupData(this.title, this.items);
}

const _navGroups = <_NavGroupData>[
  _NavGroupData('学习中心', [
    _NavItemData('首页', '/home', Icons.home_outlined, Icons.home),
    _NavItemData(
      '错题指导',
      '/wrong-question/chat',
      Icons.quiz_outlined,
      Icons.quiz,
    ),
    _NavItemData(
      '考试分析',
      '/exam/analysis',
      Icons.assignment_outlined,
      Icons.assignment,
    ),
    _NavItemData(
      '智能问答',
      '/smart-qa',
      Icons.chat_bubble_outline,
      Icons.chat_bubble,
    ),
  ]),
  _NavGroupData('学习工具', [
    _NavItemData(
      '知识图谱',
      '/home/graph',
      Icons.account_tree_outlined,
      Icons.account_tree,
    ),
    _NavItemData(
      '学习报告',
      '/profile/report',
      Icons.assessment_outlined,
      Icons.assessment,
    ),
    _NavItemData(
      '错题本',
      '/wrong-question/list',
      Icons.book_outlined,
      Icons.book,
    ),
  ]),
  _NavGroupData('我的', [
    _NavItemData('我的', '/profile', Icons.person_outline, Icons.person),
  ]),
];

/// 手机竖屏底部导航：与 `StatefulShellRoute` 的 5 个分支一一对应（index 0..4）。
const _kMobileDestinations = <NavigationDestination>[
  NavigationDestination(
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home),
    label: '首页',
  ),
  NavigationDestination(
    icon: Icon(Icons.quiz_outlined),
    selectedIcon: Icon(Icons.quiz),
    label: '错题',
  ),
  NavigationDestination(
    icon: Icon(Icons.assignment_outlined),
    selectedIcon: Icon(Icons.assignment),
    label: '考试',
  ),
  NavigationDestination(
    icon: Icon(Icons.chat_bubble_outline),
    selectedIcon: Icon(Icons.chat_bubble),
    label: '问答',
  ),
  NavigationDestination(
    icon: Icon(Icons.person_outline),
    selectedIcon: Icon(Icons.person),
    label: '我的',
  ),
];

// ── Active state helpers ─────────────────────────────────────────────────

/// Returns the path of the nav item that should appear active for [location].
///
/// Exact matches are checked first (sub-pages like /home/graph,
/// /wrong-question/list). If no exact match is found, section prefixes are
/// checked so that sub-routes like /exam/history or /profile/settings fall
/// back to their parent nav item.
String? _activeNavPath(String location) {
  // 1. Exact matches (sub-pages)
  for (final group in _navGroups) {
    for (final item in group.items) {
      if (location == item.path) return item.path;
    }
  }
  // 2. Section prefix matches (longer prefixes first to avoid false positives)
  const sectionPrefixes = <(String, String)>[
    ('/wrong-question', '/wrong-question/chat'),
    ('/exam', '/exam/analysis'),
    ('/smart-qa', '/smart-qa'),
    ('/home', '/home'),
    ('/profile', '/profile'),
  ];
  for (final (prefix, navPath) in sectionPrefixes) {
    if (location.startsWith(prefix)) return navPath;
  }
  return null;
}

/// Returns the display label for the active nav item, or a fallback.
String _activeNavLabel(String location) {
  final activePath = _activeNavPath(location);
  if (activePath == null) return '格数至理';
  for (final group in _navGroups) {
    for (final item in group.items) {
      if (item.path == activePath) return item.label;
    }
  }
  return '格数至理';
}

// ── AppShell ─────────────────────────────────────────────────────────────

/// Desktop workspace shell: dark left sidebar + slim top toolbar + content.
///
/// Replaces the former mobile bottom-tab layout. The 5 existing
/// StatefulShellRoute branches are preserved — they render inside the
/// content area with their own Scaffold+AppBar.
class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _collapsed = false;
  bool _missedReportChecked = false;

  @override
  void initState() {
    super.initState();
    // 每次进入 App（登录/启动）检查定时报告补发：已过触发点且本周期未发送 → 后台生成并保存
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkMissedReport());
  }

  Future<void> _checkMissedReport() async {
    if (_missedReportChecked) return;
    _missedReportChecked = true;
    try {
      final schedule = ReportScheduleService.loadSchedule();
      if (!ReportScheduleService.shouldTriggerMissed(
        schedule,
        DateTime.now(),
      )) {
        return;
      }
      final result = await ReportGenerator.generate(ref, days: 7);
      if (result.content.trim().isEmpty) {
        ReportScheduleService.markSent(); // 空数据也算完成本轮，避免每次进入都重试
        return;
      }
      ReportScheduleService.saveReportContent(result.content);
      ReportScheduleService.saveRecommendedIds(result.recommendedIds);
      ReportScheduleService.markSent();
    } catch (_) {
      // 静默失败：不打扰用户；打开报告页仍可手动生成 / 页面内补发
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final location = GoRouterState.of(context).uri.path;
    final studentId = ref.watch(studentIdProvider);
    final profile = ref.watch(studentProfileProvider);

    // ── 手机竖屏（≤600）：底部导航栏 ─────────────────────────────
    // 不再用左侧图标栏 + 顶部 shell header（后者会和页面自带 AppBar 叠成双标题）。
    // 页面保留各自的 AppBar 作为唯一标题栏；shell 只提供底部导航。
    if (screenWidth < 600) {
      return Scaffold(
        body: AppBranchSettle(
          trigger: widget.navigationShell.currentIndex,
          child: widget.navigationShell,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: widget.navigationShell.currentIndex,
          onDestinationSelected: (index) => widget.navigationShell.goBranch(
            index,
            // 再次点击当前 tab → 回到该分支根页（与主流 App 一致）
            initialLocation: index == widget.navigationShell.currentIndex,
          ),
          destinations: _kMobileDestinations,
        ),
      );
    }

    // ── 桌面 / 宽屏：原侧边栏工作区布局 ─────────────────────────
    // Auto-collapse on narrow screens
    final effectiveCollapsed = _collapsed || screenWidth < 800;

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            collapsed: effectiveCollapsed,
            location: location,
            studentId: studentId,
            onToggleCollapse: () => setState(() => _collapsed = !_collapsed),
          ),
          Expanded(
            child: Column(
              children: [
                _Header(
                  location: location,
                  profile: profile,
                  collapsed: effectiveCollapsed,
                  onToggleCollapse: () =>
                      setState(() => _collapsed = !_collapsed),
                ),
                Expanded(
                  child: AppBranchSettle(
                    // 只监听分支索引：子树不换 key，各分支状态与滚动位置全部保留
                    trigger: widget.navigationShell.currentIndex,
                    child: widget.navigationShell,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar ──────────────────────────────────────────────────────────────

/// Dark left sidebar with grouped nav, logo, and footer.
class _Sidebar extends StatelessWidget {
  final bool collapsed;
  final String location;
  final String studentId;
  final VoidCallback onToggleCollapse;

  const _Sidebar({
    required this.collapsed,
    required this.location,
    required this.studentId,
    required this.onToggleCollapse,
  });

  static const double _expandedWidth = 232;
  static const double _collapsedWidth = 68;

  @override
  Widget build(BuildContext context) {
    final width = collapsed ? _collapsedWidth : _expandedWidth;
    final activePath = _activeNavPath(location);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: width,
      child: Material(
        color: _SidebarPalette.bg,
        child: Column(
          children: [
            // Logo area
            _LogoArea(collapsed: collapsed),
            // Nav
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                children: [
                  for (final group in _navGroups) ...[
                    if (!collapsed)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 8,
                          top: 10,
                          bottom: 4,
                        ),
                        child: Text(
                          group.title,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _SidebarPalette.groupTitle,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    for (final item in group.items)
                      _NavItem(
                        item: item,
                        active: activePath == item.path,
                        collapsed: collapsed,
                      ),
                  ],
                ],
              ),
            ),
            // Bottom: student-id chip + collapse button
            _SidebarFooter(
              collapsed: collapsed,
              studentId: studentId,
              onToggleCollapse: onToggleCollapse,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Logo area ────────────────────────────────────────────────────────────

class _LogoArea extends StatelessWidget {
  final bool collapsed;
  const _LogoArea({required this.collapsed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 16),
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0A84FF), Color(0xFF007AFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.science, color: Colors.white, size: 18),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 10),
            const AppReveal(
              duration: AppMotion.fast,
              offset: Offset(-8, 0),
              beginScale: 1,
              child: Text(
                '格数至理',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _SidebarPalette.logoText,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Nav item ─────────────────────────────────────────────────────────────

/// A single sidebar nav item with icon + label, hover feedback, and active
/// accent. When [collapsed] is true, only the icon is shown and a tooltip
/// reveals the label on hover.
class _NavItem extends StatefulWidget {
  final _NavItemData item;
  final bool active;
  final bool collapsed;

  const _NavItem({
    required this.item,
    required this.active,
    required this.collapsed,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isCollapsed = widget.collapsed;
    final isActive = widget.active;

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.only(bottom: 2),
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? 0 : 10,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: isActive
            ? _SidebarPalette.activeBg
            : _hovered
            ? _SidebarPalette.hover
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: isCollapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          // 激活时图标轻微放大，outline/filled 之间交叉淡入而不是硬切
          AnimatedScale(
            scale: isActive ? 1.06 : 1,
            duration: AppMotion.resolve(context, AppMotion.standard),
            curve: AppMotion.spring,
            child: AnimatedSwitcher(
              duration: AppMotion.resolve(context, AppMotion.fast),
              switchInCurve: AppMotion.enter,
              switchOutCurve: AppMotion.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.86, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: Icon(
                isActive ? widget.item.activeIcon : widget.item.icon,
                key: ValueKey<bool>(isActive),
                size: 20,
                color: isActive
                    ? _SidebarPalette.activeText
                    : _SidebarPalette.inactiveText,
              ),
            ),
          ),
          if (!isCollapsed) ...[
            const SizedBox(width: 10),
            Expanded(
              // 展开侧栏时标签从左侧滑入，避免整条侧栏“跳”一下
              child: AppReveal(
                duration: AppMotion.fast,
                offset: const Offset(-6, 0),
                beginScale: 1,
                child: AnimatedDefaultTextStyle(
                  duration: AppMotion.resolve(context, AppMotion.standard),
                  curve: AppMotion.enter,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive
                        ? _SidebarPalette.activeText
                        : _SidebarPalette.inactiveText,
                  ),
                  child: Text(
                    widget.item.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (isCollapsed) {
      content = Tooltip(
        message: widget.item.label,
        waitDuration: const Duration(milliseconds: 400),
        child: content,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AppPressScale(
        pressedScale: isCollapsed ? 0.92 : 0.97,
        hoverScale: isCollapsed ? 1 : 1.01,
        child: GestureDetector(
          onTap: () => context.go(widget.item.path),
          child: content,
        ),
      ),
    );
  }
}

// ── Sidebar footer ───────────────────────────────────────────────────────

class _SidebarFooter extends StatelessWidget {
  final bool collapsed;
  final String studentId;
  final VoidCallback onToggleCollapse;

  const _SidebarFooter({
    required this.collapsed,
    required this.studentId,
    required this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: _SidebarPalette.divider, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!collapsed && studentId.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _SidebarPalette.chipBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.badge_outlined,
                    size: 14,
                    color: _SidebarPalette.chipText,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      studentId,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _SidebarPalette.chipText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          _CollapseButton(collapsed: collapsed, onPressed: onToggleCollapse),
        ],
      ),
    );
  }
}

// ── Collapse button ──────────────────────────────────────────────────────

class _CollapseButton extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onPressed;

  const _CollapseButton({required this.collapsed, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AppPressScale(
      pressedScale: 0.860,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: collapsed ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : 10,
            vertical: 8,
          ),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              // 同一个 chevron 旋转，而不是换图标 —— 过渡更连续
              AnimatedRotation(
                turns: collapsed ? 0.5 : 0,
                duration: AppMotion.resolve(context, AppMotion.navigation),
                curve: AppMotion.spring,
                child: const Icon(
                  Icons.chevron_left,
                  size: 18,
                  color: _SidebarPalette.inactiveText,
                ),
              ),
              if (!collapsed) ...[
                const SizedBox(width: 8),
                const AppReveal(
                  duration: AppMotion.fast,
                  offset: Offset(-6, 0),
                  beginScale: 1,
                  child: Text(
                    '收起',
                    style: TextStyle(
                      fontSize: 12,
                      color: _SidebarPalette.inactiveText,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────

/// Slim 48px white toolbar. Left = current module title; right = student
/// avatar + name + settings icon. Existing pages keep their own AppBars for
/// page-level actions.
class _Header extends StatelessWidget {
  final String location;
  final StudentProfile profile;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  const _Header({
    required this.location,
    required this.profile,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final title = _activeNavLabel(location);
    final displayName = profile.name.isNotEmpty ? profile.name : '同学';

    return Material(
      color: Colors.white,
      child: Container(
        height: 48,
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _MotionIconButton(
              icon: Icon(collapsed ? Icons.menu : Icons.menu_open, size: 20),
              color: AppColors.mutedForeground,
              onPressed: onToggleCollapse,
              tooltip: collapsed ? '展开侧栏' : '收起侧栏',
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: AppMotion.resolve(context, AppMotion.standard),
              switchInCurve: AppMotion.enter,
              switchOutCurve: AppMotion.exit,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previousChildren, ?currentChild],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.35),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                title,
                key: ValueKey<String>(title),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.foreground,
                ),
              ),
            ),
            const Spacer(),
            _HeaderAvatar(profile: profile),
            const SizedBox(width: 8),
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(width: 12),
            _MotionIconButton(
              icon: const Icon(Icons.settings_outlined, size: 20),
              color: AppColors.mutedForeground,
              onPressed: () => context.go('/profile/settings'),
              tooltip: '设置',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header avatar ──────────────────────────────────────────────
class _MotionIconButton extends StatelessWidget {
  final Widget icon;
  final Color color;
  final VoidCallback? onPressed;
  final String tooltip;
  final VisualDensity visualDensity;

  const _MotionIconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.tooltip,
    required this.visualDensity,
  });

  @override
  Widget build(BuildContext context) {
    return AppPressScale(
      pressedScale: 0.86,
      enabled: onPressed != null,
      child: IconButton(
        icon: icon,
        color: color,
        onPressed: onPressed,
        tooltip: tooltip,
        visualDensity: visualDensity,
      ),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  final StudentProfile profile;
  const _HeaderAvatar({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile.hasAvatar) {
      try {
        final base64Str = profile.avatarBase64.contains(',')
            ? profile.avatarBase64.split(',').last
            : profile.avatarBase64;
        final bytes = base64Decode(base64Str);
        return CircleAvatar(radius: 14, backgroundImage: MemoryImage(bytes));
      } catch (_) {
        return _defaultAvatar();
      }
    }
    return _defaultAvatar();
  }

  Widget _defaultAvatar() {
    return const CircleAvatar(
      radius: 14,
      backgroundColor: AppColors.primary,
      child: Icon(Icons.person, size: 16, color: Colors.white),
    );
  }
}
