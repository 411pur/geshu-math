import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geshu_math/features/wrong_question/widgets/wrong_question_delete_dialog.dart';

void main() {
  testWidgets('delete confirmation can be cancelled', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await confirmWrongQuestionDeletion(context);
            },
            child: const Text('删除错题'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('删除错题'));
    await tester.pumpAndSettle();
    expect(find.text('删除后将无法恢复，确定要删除这道错题吗？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('delete confirmation requires the explicit red delete action', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await confirmWrongQuestionDeletion(context);
            },
            child: const Text('删除错题'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('删除错题'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
