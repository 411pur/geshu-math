import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/wrong_question_entity.dart';
import '../../wrong_question/pages/wrong_question_detail_page.dart';
import '../../wrong_question/providers/wrong_question_providers.dart';

void openAnalyticsQuestion(
  BuildContext context,
  WidgetRef ref,
  WrongQuestion question,
) {
  final source = ref.read(wrongQuestionDataSourceProvider);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WrongQuestionDetailPage(
        item: question,
        onMasteryChanged: question.id == null
            ? null
            : (value) => source.updateMastery(question.id!, value),
        onFavoritedChanged: question.id == null
            ? null
            : (_) => source.toggleFavorite(question.id!),
        onTagsChanged: question.id == null
            ? null
            : (value) => source.updateTags(question.id!, value),
      ),
    ),
  );
}

Future<void> showAnalyticsQuestions(
  BuildContext context,
  String title,
  List<WrongQuestion> questions,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetContext) => Consumer(
    builder: (_, ref, _) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .72,
      child: Column(
        children: [
          ListTile(
            title: Text(
              '$title · ${questions.length} 道',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            trailing: IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(sheetContext),
            ),
          ),
          const Divider(height: 1),
          if (questions.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('暂无对应错题')),
          Expanded(
            child: ListView.builder(
              itemCount: questions.length,
              itemBuilder: (_, index) {
                final q = questions[index];
                return ListTile(
                  title: Text(
                    q.questionText.isEmpty ? '图片题目' : q.questionText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(q.subTopic ?? q.topic ?? '未分类'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    openAnalyticsQuestion(context, ref, q);
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  ),
);
