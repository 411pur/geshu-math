import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geshu_math/core/theme/app_theme.dart';
import 'package:geshu_math/domain/entities/wrong_question_entity.dart';
import 'package:geshu_math/features/report/models/learning_memory.dart';
import 'package:geshu_math/features/report/models/wrong_question_analytics.dart';
import 'package:geshu_math/features/report/widgets/learning_report_summary_card.dart';

void main() {
  final now = DateTime(2026, 10, 19);
  final question = WrongQuestion(
    id: 1,
    topic: '函数',
    subTopic: '导数与单调性',
    questionText: '判断函数在区间上的单调性。',
    createdAt: now.millisecondsSinceEpoch,
    mastery: 0,
  );

  for (final width in [360.0, 1200.0]) {
    testWidgets('summary card is compact and usable at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var practiced = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: LearningReportSummaryCard(
                data: WrongQuestionAnalytics([question], now: now, days: 7),
                days: 7,
                nextSuggestion: LearningSuggestion(
                  question,
                  '先回顾定义域，再判断导数符号。',
                  3,
                ),
                onPractice: () => practiced = true,
                onAddQuestion: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('近 7 天学习概览'), findsOneWidget);
      expect(find.text('本期收录'), findsOneWidget);
      expect(find.text('待巩固'), findsOneWidget);
      expect(find.text('导数与单调性'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('开始练习'));
      expect(practiced, isTrue);
    });
  }

  testWidgets('empty summary uses a real add-question action', (tester) async {
    var added = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: LearningReportSummaryCard(
              data: WrongQuestionAnalytics([], now: now, days: 7),
              days: 7,
              nextSuggestion: null,
              onPractice: null,
              onAddQuestion: () => added = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无优先练习'), findsOneWidget);
    await tester.tap(find.text('去添加错题'));
    expect(added, isTrue);
    expect(tester.takeException(), isNull);
  });
}
