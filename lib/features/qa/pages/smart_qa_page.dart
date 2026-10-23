import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/network/network_provider.dart';
import '../../../core/network/sse_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/chat_message_entity.dart';
import '../../../shared/widgets/styled_markdown.dart';

class SmartQAPage extends ConsumerStatefulWidget {
  const SmartQAPage({super.key});

  @override
  ConsumerState<SmartQAPage> createState() => _SmartQAPageState();
}

class _SmartQAPageState extends ConsumerState<SmartQAPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <ChatMessage>[];
  bool _streaming = false;
  final _suggestions = ['二次函数的最值怎么求？', '如何判断一元二次方程的根的情况？', '三角函数诱导公式怎么记？', '数列求和有哪些常用方法？'];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _streaming) return;
    setState(() {
      _messages.add(
        ChatMessage(
          role: MessageRole.user,
          content: text,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _streaming = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final client = ref.read(aliyunApiClientProvider);
      String fullAnswer = '';
      await for (final event in client.sendQaMessage(query: text)) {
        if (event is MessageChunk) {
          fullAnswer += event.answer;
          if (_messages.isNotEmpty &&
              _messages.last.role == MessageRole.assistant) {
            setState(
              () => _messages[_messages.length - 1] = ChatMessage(
                role: MessageRole.assistant,
                content: fullAnswer,
                timestamp: DateTime.now().millisecondsSinceEpoch,
                isStreaming: true,
              ),
            );
          } else {
            setState(
              () => _messages.add(
                ChatMessage(
                  role: MessageRole.assistant,
                  content: fullAnswer,
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  isStreaming: true,
                ),
              ),
            );
          }
          _scrollToBottom();
        } else if (event is MessageEnd) {
          setState(() {
            _messages.add(
              ChatMessage(
                role: MessageRole.assistant,
                content: event.fullAnswer,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            );
            _streaming = false;
          });
        } else if (event is StreamError) {
          setState(() {
            _messages.add(
              ChatMessage(
                role: MessageRole.assistant,
                content: '出错: ${event.message}',
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            );
            _streaming = false;
          });
        }
      }
    } catch (error) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: MessageRole.assistant,
            content: '请求失败: $error',
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        _streaming = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppMotion.standard,
          curve: AppMotion.enter,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('智能问答'),
      actions: [
        AppPressScale(
          pressedScale: 0.86,
          enabled: _messages.isNotEmpty,
          child: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空',
            onPressed: _messages.isEmpty
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('清空对话'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('取消'),
                        ),
                        AppPressScale(
                          pressedScale: 0.86,
                          child: FilledButton(
                            onPressed: () {
                              setState(() => _messages.clear());
                              Navigator.pop(dialogContext);
                            },
                            child: const Text('确定'),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? _emptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, index) => AppReveal(
                    index: index,
                    offset: const Offset(0, 10),
                    child: _bubble(_messages[index]),
                  ),
                ),
        ),
        _inputBar(),
      ],
    ),
  );

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.secondarySystem,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat,
              size: 36,
              color: AppColors.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '开始提问数学问题吧',
            style: TextStyle(color: AppColors.mutedForeground, fontSize: 16),
          ),
          const SizedBox(height: 24),
          ..._suggestions.map(
            (suggestion) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppPressScale(
                pressedScale: 0.86,
                child: ActionChip(
                  label: Text(
                    suggestion,
                    style: const TextStyle(color: AppColors.primary),
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.72),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  elevation: 0,
                  onPressed: () => _send(suggestion),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _bubble(ChatMessage message) {
    final isUser = message.role == MessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.primary
              : Colors.white.withValues(alpha: 0.72),
          border: isUser
              ? null
              : Border.all(color: Colors.black.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(12).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: isUser ? null : const Radius.circular(4),
          ),
        ),
        child: isUser
            ? Text(
                message.content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
              )
            : StyledMarkdown(data: message.content, fontSize: 14),
      ),
    );
  }

  Widget _inputBar() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.72),
      border: Border(
        top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 4,
          offset: const Offset(0, -1),
        ),
      ],
    ),
    child: SafeArea(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '输入数学问题...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                filled: true,
                fillColor: AppColors.secondarySystem,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AppPressScale(
            pressedScale: 0.84,
            enabled: !_streaming,
            child: CircleAvatar(
              backgroundColor: AppColors.primary,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _streaming ? null : () => _send(_controller.text),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
