/// A single message in a chat conversation.
class ChatMessage {
  final MessageRole role;
  final String content;
  final int timestamp;
  final bool isStreaming;

  const ChatMessage({
    this.role = MessageRole.user,
    required this.content,
    this.timestamp = 0,
    this.isStreaming = false,
  });

  ChatMessage copyWith({
    MessageRole? role,
    String? content,
    int? timestamp,
    bool? isStreaming,
  }) =>
      ChatMessage(
        role: role ?? this.role,
        content: content ?? this.content,
        timestamp: timestamp ?? this.timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
      );
}

enum MessageRole { user, assistant }