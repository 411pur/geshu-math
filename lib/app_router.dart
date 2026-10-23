import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

import '../features/home/pages/home_page.dart';
import '../features/home/pages/home_overview_page.dart';
import '../features/home/pages/profile_page.dart';
import '../features/home/pages/settings_page.dart';
import '../features/knowledge/pages/knowledge_graph_page.dart';
import '../features/knowledge/pages/knowledge_tree_page.dart';
import '../features/wrong_question/pages/wrong_question_chat_page.dart';
import '../features/wrong_question/pages/wrong_question_list_page.dart';
import '../features/exam/pages/exam_analysis_page.dart';
import '../features/exam/pages/exam_history_page.dart';
import '../features/exam/pages/exam_detail_page.dart';
import '../features/qa/pages/smart_qa_page.dart';
import '../features/scan/pages/scan_preview_page.dart';
import '../features/report/pages/learning_report_page.dart';
import '../features/report/pages/student_portrait_page.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// ── Branch navigator keys (preserve state across tab switches) ────
final _knowledgeKey = GlobalKey<NavigatorState>();
final _wrongQKey = GlobalKey<NavigatorState>();
final _examKey = GlobalKey<NavigatorState>();
final _qaKey = GlobalKey<NavigatorState>();
final _profileKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/',
      redirect: (_, _) => '/home',
    ),
    GoRoute(
      path: '/scan',
      builder: (_, _) => const ScanPreviewPage(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          HomePage(navigationShell: navigationShell),
      branches: [
        // ── 首页概览 ──────────────────────────────────────
        StatefulShellBranch(
          navigatorKey: _knowledgeKey,
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const HomeOverviewPage(),
              routes: [
                GoRoute(
                  path: 'graph',
                  builder: (_, _) => const KnowledgeGraphPage(),
                ),
                GoRoute(
                  path: 'tree',
                  builder: (_, _) => const KnowledgeTreePage(),
                ),
              ],
            ),
          ],
        ),
        // ── 错题指导 ──────────────────────────────────────
        StatefulShellBranch(
          navigatorKey: _wrongQKey,
          routes: [
            GoRoute(
              path: '/wrong-question/chat',
              builder: (_, _) => const WrongQuestionChatPage(),
            ),
            GoRoute(
              path: '/wrong-question/list',
              builder: (_, _) => const WrongQuestionListPage(),
            ),
          ],
        ),
        // ── 考试分析 ──────────────────────────────────────
        StatefulShellBranch(
          navigatorKey: _examKey,
          routes: [
            GoRoute(
              path: '/exam/analysis',
              builder: (_, _) => const ExamAnalysisPage(),
            ),
            GoRoute(
              path: '/exam/history',
              builder: (_, _) => const ExamHistoryPage(),
            ),
            GoRoute(
              path: '/exam/detail/:id',
              builder: (_, state) => ExamDetailPage(
                id: int.parse(state.pathParameters['id']!),
              ),
            ),
          ],
        ),
        // ── 智能问答 ──────────────────────────────────────
        StatefulShellBranch(
          navigatorKey: _qaKey,
          routes: [
            GoRoute(
              path: '/smart-qa',
              builder: (_, _) => const SmartQAPage(),
            ),
          ],
        ),
        // ── 我的 ──────────────────────────────────────────
        StatefulShellBranch(
          navigatorKey: _profileKey,
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, _) => const ProfilePage(),
              routes: [
                GoRoute(
                  path: 'portrait',
                  builder: (_, _) => const StudentPortraitPage(),
                ),
                GoRoute(
                  path: 'report',
                  builder: (_, _) => const LearningReportPage(),
                ),
                GoRoute(
                  path: 'settings',
                  builder: (_, _) => const SettingsPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
