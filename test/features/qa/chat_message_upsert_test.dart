import 'package:flutter_test/flutter_test.dart';
import 'package:geshu_math/domain/entities/chat_message_entity.dart';
import 'package:geshu_math/features/qa/chat_message_upsert.dart';

ChatMessage _assistant(String content, {bool streaming = false}) => ChatMessage(
  role: MessageRole.assistant,
  content: content,
  timestamp: 1,
  isStreaming: streaming,
);

void main() {
  test('流式分片持续更新同一个助手气泡', () {
    final messages = <ChatMessage>[_assistant('勾', streaming: true)];
    upsertAssistantMessage(messages, _assistant('勾股', streaming: true));
    expect(messages, hasLength(1));
    expect(messages.single.content, '勾股');
  });

  test('MessageEnd 替换流式气泡而不是追加重复回答', () {
    final messages = <ChatMessage>[
      const ChatMessage(role: MessageRole.user, content: '问题', timestamp: 0),
      _assistant('完整回答', streaming: true),
    ];
    upsertAssistantMessage(messages, _assistant('完整回答'));
    expect(messages, hasLength(2));
    expect(messages.last.content, '完整回答');
    expect(messages.last.isStreaming, isFalse);
  });

  test('首个回答事件直接创建助手气泡', () {
    final messages = <ChatMessage>[
      const ChatMessage(role: MessageRole.user, content: '问题', timestamp: 0),
    ];
    upsertAssistantMessage(messages, _assistant('回答', streaming: true));
    expect(messages, hasLength(2));
    expect(messages.last.role, MessageRole.assistant);
  });
}
