import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/chat_message_entity.dart';

/// Chat message list as a mutable notifier.
class ChatMessagesNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() => [];

  void add(ChatMessage msg) {
    state = [...state, msg];
  }

  void updateLast(ChatMessage updated) {
    if (state.isEmpty) return;
    state = [
      ...state.sublist(0, state.length - 1),
      updated,
    ];
  }

  void clear() {
    state = [];
  }
}

final chatMessagesProvider = NotifierProvider<ChatMessagesNotifier, List<ChatMessage>>(
  ChatMessagesNotifier.new,
);

/// Whether a message is currently streaming in.
class IsStreamingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setStreaming(bool value) => state = value;
}

final isStreamingProvider = NotifierProvider<IsStreamingNotifier, bool>(
  IsStreamingNotifier.new,
);

/// Suggested quick-start questions.
final suggestedQuestionsProvider = Provider<List<String>>((ref) => [
  '二次函数的最值怎么求？',
  '如何判断一元二次方程的根的情况？',
  '三角函数诱导公式怎么记？',
  '数列求和有哪些常用方法？',
  '椭圆与双曲线的离心率怎么求？',
]);