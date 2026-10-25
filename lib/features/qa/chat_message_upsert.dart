import '../../domain/entities/chat_message_entity.dart';

/// 流式回答只在同一个 assistant 气泡里更新；结束时替换该气泡而不是再追加一份。
void upsertAssistantMessage(List<ChatMessage> messages, ChatMessage message) {
  if (messages.isNotEmpty && messages.last.role == MessageRole.assistant) {
    messages[messages.length - 1] = message;
  } else {
    messages.add(message);
  }
}
