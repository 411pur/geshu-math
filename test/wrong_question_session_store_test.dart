import 'package:flutter_test/flutter_test.dart';
import 'package:geshu_math/features/wrong_question/pages/wrong_question_session_store.dart';

void main() {
  test('session history round-trips diagnosis and archive flags', () {
    final sessions = <Map<String, dynamic>>[
      {
        'id': 'session-1',
        'title': '函数单调性',
        'updatedAt': 1,
        'pinned': true,
        'archived': false,
        'state': {
          'expertMode': false,
          'lessonQuestionText': '怎样判断函数单调性',
          'analysis': '先求定义域，再判断导数符号',
        },
      },
    ];

    final restored = WrongQuestionSessionStore.decode(
      WrongQuestionSessionStore.encode(sessions),
    );

    expect(restored, hasLength(1));
    expect(restored.single['title'], '函数单调性');
    expect(restored.single['pinned'], isTrue);
    expect(
      (restored.single['state'] as Map<String, dynamic>)['expertMode'],
      isFalse,
    );
  });

  test('main and archived sessions survive subsequent writes', () {
    final sessions = <Map<String, dynamic>>[
      {'id': 'active', 'archived': false, 'state': <String, dynamic>{}},
      {'id': 'old', 'archived': true, 'state': <String, dynamic>{}},
    ];
    final restored = WrongQuestionSessionStore.decode(
      WrongQuestionSessionStore.encode(sessions),
    );
    expect(restored.where((item) => item['archived'] == true), hasLength(1));
  });

  test('invalid or unknown history is rejected without partial restore', () {
    expect(
      () => WrongQuestionSessionStore.decode('not-json'),
      throwsA(anything),
    );
    expect(
      () => WrongQuestionSessionStore.decode('{"version":99,"sessions":[]}'),
      throwsFormatException,
    );
  });
}
