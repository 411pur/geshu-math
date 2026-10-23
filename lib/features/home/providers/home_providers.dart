import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../wrong_question/providers/wrong_question_providers.dart';
import '../../exam/providers/exam_providers.dart';

final homeStatsProvider = FutureProvider<HomeStats>((ref) async {
  final wqDs = ref.watch(wrongQuestionDataSourceProvider);
  final examDs = ref.watch(examDataSourceProvider);
  final wqCount = wqDs.count();
  final exams = examDs.getAllHistory(limit: 10);
  final avgScore = exams.isNotEmpty
      ? exams.fold<double>(0, (s, e) => s + (e.studentScore ?? 0)) / exams.length
      : null;
  return HomeStats(wrongQuestionCount: wqCount, examCount: exams.length, averageScore: avgScore);
});

class HomeStats {
  final int wrongQuestionCount, examCount;
  final double? averageScore;
  const HomeStats({required this.wrongQuestionCount, required this.examCount, this.averageScore});
}