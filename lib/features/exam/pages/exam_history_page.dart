import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'exam_detail_page.dart';
import '../../../core/motion/app_motion.dart';
import '../../../shared/widgets/empty_state_widget.dart';

class ExamHistoryPage extends ConsumerWidget {
  const ExamHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exams = List.generate(
      3,
      (i) => (
        name: '高${10 + i}数学${['月考', '期中', '期末'][i]}',
        date: '2026-0${6 - i}-01',
        score: 72.0 + i * 8,
        total: 100.0,
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('考情历史')),
      body: exams.isEmpty
          ? const EmptyStateWidget(message: '暂无考试记录')
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: exams.length,
              itemBuilder: (_, i) => AppReveal(
                index: i,
                child: _card(context, exams[i], i + 1),
              ),
            ),
    );
  }

  Widget _card(BuildContext context, dynamic e, int id) {
    final rate = e.score / e.total;
    final color = rate >= 0.8 ? Colors.green : rate >= 0.6 ? Colors.orange : Colors.red;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text('${e.score.toInt()}', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ),
        title: Text(e.name),
        subtitle: Text('${e.date} · ${e.score}/${e.total} 分'),
        trailing: Text(
          '${(rate * 100).toInt()}%',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamDetailPage(id: id))),
      ),
    );
  }
}