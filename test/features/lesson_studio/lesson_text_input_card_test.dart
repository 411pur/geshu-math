import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geshu_math/features/lesson_studio/widgets/lesson_text_input_card.dart';
import 'package:geshu_math/shared/widgets/styled_markdown.dart';

const _rawQuestion =
    r'实数 $a,b$ 满足 $\frac{1}{a^3}e^{a^2-b}+2a^2=6\ln a+2b+1$，'
    r'$c\in\mathbb{R}$，则 $(a-c)^2+(b+c)^2$ 的最小值是______。';

void main() {
  test('LaTeX 题干转换后保留常用运算与集合符号', () {
    final text = texToUnicode(_rawQuestion);
    expect(text, contains('(1)/(a³)'));
    expect(text, contains('e^(a²-b)'));
    expect(text, contains('6ln a'));
    expect(text, contains('c∈R'));
    expect(text, isNot(contains('\\frac')));
    expect(text, isNot(contains('\\ln')));
  });

  testWidgets('预填题干默认显示数学预览，并可切换编辑与返回预览', (tester) async {
    final controller = TextEditingController(text: _rawQuestion);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _Harness(controller: controller)),
      ),
    );

    expect(find.text('题目预览'), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-text-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-text-input')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('lesson-text-edit')));
    await tester.pumpAndSettle();
    expect(find.text('题干输入'), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-text-input')), findsOneWidget);
    expect(controller.text, _rawQuestion);

    await tester.enterText(
      find.byKey(const ValueKey('lesson-text-input')),
      r'求 $x^2$ 的最小值',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lesson-text-done')));
    await tester.pumpAndSettle();

    expect(find.text('题目预览'), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-text-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-text-input')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Harness extends StatefulWidget {
  final TextEditingController controller;

  const _Harness({required this.controller});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool previewing = true;

  @override
  Widget build(BuildContext context) {
    return LessonTextInputCard(
      controller: widget.controller,
      previewing: previewing,
      onEdit: () => setState(() => previewing = false),
      onDone: () => setState(() => previewing = true),
      onChanged: (_) => setState(() {}),
    );
  }
}
