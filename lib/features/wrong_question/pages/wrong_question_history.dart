part of 'wrong_question_chat_page.dart';

// Local session snapshots are independent of the curated wrong-question book.
extension _WrongQuestionHistory on _WrongQuestionChatPageState {
  static const _historyKey = 'wrong_question_sessions_v1';

  void _historyNotice(String message) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  void _readHistory() {
    try {
      final raw = web.window.localStorage.getItem(_historyKey);
      if (raw == null) return;
      _sessions.addAll(WrongQuestionSessionStore.decode(raw));
    } catch (_) {
      _historyWriteFailed = true;
      _historyNotice('会话记录读取失败，已保留原数据，请勿清理浏览器存储。');
    }
  }

  bool _writeHistory({bool notify = true}) {
    if (_historyWriteFailed) return false;
    try {
      web.window.localStorage.setItem(
        _historyKey,
        WrongQuestionSessionStore.encode(_sessions),
      );
      return true;
    } catch (_) {
      if (notify) _historyNotice('会话未能保存，浏览器存储可能已满。请保留当前页面。');
      return false;
    }
  }

  Map<String, dynamic> _snapshot() => {
    'expertMode': _expertMode,
    'lessonQuestionText': _lessonQuestionText,
    'analysis': _analysis,
    'solution': _solution,
    'difficulty': _difficulty,
    'originalQuestion': _originalQuestion,
    'questionImageBase64': _questionImageBase64,
    'expertRound': _expertRound,
    'expertDone': _expertDone,
    'expertRetryCount': _expertRetryCount,
    'expertResultBubbleCount': _expertResultBubbleCount,
    'expertImageBase64': _expertImageBase64,
    'expertAiUseImage': _expertAiUseImage,
    'expertQuestionText': _expertQuestionText,
    'savedWqId': _savedWqId,
    'error': _error,
    'expertError': _expertError,
    'knowledgePoints': _knowledgePoints,
    'guidance': _guidanceResult?.toJson(),
    'quickFollowUps': _quickFollowUps.map((e) => [e.$1, e.$2]).toList(),
    'treeNode': _treeNode.name,
    'turns': _expertTurns,
    'bubbles': _expertBubbles
        .map(
          (e) => {'user': e.isUser, 'content': e.content, 'options': e.options},
        )
        .toList(),
    'expertResult': _expertResult,
    'interrupted': _loading || _expertLoading,
    'partial': _streamText,
    'draft': _controller.text,
  };

  void _saveSession({bool notify = true}) {
    if (_historyRestoring) return;
    final hasContent = _expertMode
        ? _expertQuestionText != null || _expertBubbles.isNotEmpty
        : _lessonQuestionText.isNotEmpty ||
              _questionImageBase64 != null ||
              _analysis != null;
    if (!hasContent) return;
    _sessionId ??= DateTime.now().microsecondsSinceEpoch.toString();
    final index = _sessions.indexWhere((s) => s['id'] == _sessionId);
    final old = index < 0 ? <String, dynamic>{} : _sessions[index];
    var title = _expertMode && _expertBubbles.isNotEmpty
        ? _expertBubbles.first.content
        : _originalQuestion;
    if (title.trim().isEmpty) title = _lessonQuestionText;
    if (title.trim().isEmpty) title = '图片错题';
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    final entry = <String, dynamic>{
      'id': _sessionId,
      'title': title,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'pinned': old['pinned'] ?? false,
      'archived': old['archived'] ?? false,
      'state': jsonDecode(jsonEncode(_snapshot())),
    };
    if (index < 0) {
      _sessions.add(entry);
    } else {
      _sessions[index] = entry;
    }
    _writeHistory(notify: notify);
  }

  void _restoreSnapshot(Map<String, dynamic> data) {
    _expertMode = data['expertMode'] as bool? ?? false;
    _lessonQuestionText = data['lessonQuestionText'] as String? ?? '';
    _analysis = data['analysis'] as String?;
    _solution = data['solution'] as String?;
    _difficulty = data['difficulty'] as String? ?? '';
    _originalQuestion = data['originalQuestion'] as String? ?? '';
    _questionImageBase64 = data['questionImageBase64'] as String?;
    _expertRound = data['expertRound'] as int? ?? 0;
    _expertDone = data['expertDone'] as bool? ?? false;
    _expertRetryCount = data['expertRetryCount'] as int? ?? 0;
    _expertResultBubbleCount = data['expertResultBubbleCount'] as int? ?? 0;
    _expertImageBase64 = data['expertImageBase64'] as String?;
    _expertAiUseImage = data['expertAiUseImage'] as bool? ?? true;
    _expertQuestionText = data['expertQuestionText'] as String?;
    _savedWqId = data['savedWqId'] as int?;
    _error = data['error'] as String?;
    _expertError = data['expertError'] as String?;
    _knowledgePoints = List<String>.from(data['knowledgePoints'] ?? []);
    _guidanceResult = data['guidance'] == null
        ? null
        : GuidanceResult.fromJson(Map<String, dynamic>.from(data['guidance']));
    _quickFollowUps.clear();
    for (final e in data['quickFollowUps'] ?? []) {
      _quickFollowUps.add((e[0] as String, e[1] as String));
    }
    _treeNode = _ExpertNode.values.firstWhere(
      (e) => e.name == data['treeNode'],
      orElse: () => _ExpertNode.root,
    );
    _expertTurns.clear();
    for (final e in data['turns'] ?? []) {
      _expertTurns.add(Map<String, String>.from(e));
    }
    _expertBubbles.clear();
    for (final e in data['bubbles'] ?? []) {
      _expertBubbles.add(
        _ExpertBubble(
          isUser: e['user'] as bool,
          content: e['content'] as String,
          options: List<String>.from(e['options'] ?? []),
        ),
      );
    }
    _expertResult = data['expertResult'] == null
        ? null
        : Map<String, dynamic>.from(data['expertResult']);
    _loading = false;
    _expertLoading = false;
    _pickedImage = null;
    _streamBuf.clear();
    _streamText = null;
    _controller.text = data['draft'] as String? ?? '';
    if (data['interrupted'] == true) {
      const notice = '上次生成已中断，请重试。';
      if (_expertMode) {
        _expertError = notice;
      } else {
        _error = notice;
      }
      if (!_expertMode && _analysis == null && _controller.text.isEmpty) {
        _controller.text = _lessonQuestionText.isEmpty
            ? '请分析这道题'
            : _lessonQuestionText;
      }
    }
  }

  void _newHistorySession({bool? expert}) {
    if (_loading || _expertLoading) return;
    _saveSession();
    _historyTimer?.cancel();
    _historyRestoring = true;
    setState(() {
      _restoreSnapshot({'expertMode': expert ?? _expertMode});
      _sessionId = null;
    });
    _historyRestoring = false;
  }

  void _switchHistoryMode(bool expert) {
    if (_expertMode == expert || _loading || _expertLoading) return;
    _newHistorySession(expert: expert);
  }

  Future<void> _openHistory() async {
    _saveSession();
    var archived = false;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭会话记录',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondary, child) =>
          SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
      pageBuilder: (dialogContext, _, _) => StatefulBuilder(
        builder: (context, update) {
          final entries =
              _sessions
                  .where((e) => (e['archived'] == true) == archived)
                  .toList()
                ..sort((a, b) {
                  final pin = (b['pinned'] == true ? 1 : 0).compareTo(
                    a['pinned'] == true ? 1 : 0,
                  );
                  return pin != 0
                      ? pin
                      : (b['updatedAt'] as int).compareTo(
                          a['updatedAt'] as int,
                        );
                });
          final busy = _loading || _expertLoading;
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: MediaQuery.sizeOf(
                  context,
                ).width.clamp(0, 380).toDouble(),
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '会话记录',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭',
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(dialogContext),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: busy
                                    ? null
                                    : () {
                                        Navigator.pop(dialogContext);
                                        _newHistorySession();
                                      },
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('新建会话'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text('已归档'),
                              selected: archived,
                              onSelected: (v) => update(() => archived = v),
                            ),
                          ],
                        ),
                      ),
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            '正在生成，完成后可切换会话',
                            style: TextStyle(
                              color: AppColors.mutedForeground,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: entries.isEmpty
                            ? Center(
                                child: Text(
                                  archived ? '暂无归档会话' : '提交题目后，会话会自动保存在这里',
                                  style: const TextStyle(
                                    color: AppColors.mutedForeground,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                itemCount: entries.length,
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                                  final state = Map<String, dynamic>.from(
                                    entry['state'],
                                  );
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: ListTile(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      selected: entry['id'] == _sessionId,
                                      selectedTileColor: AppColors.primary
                                          .withValues(alpha: 0.08),
                                      hoverColor: AppColors.secondarySystem,
                                      title: Text(
                                        entry['title'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '${state['expertMode'] == true ? '专家版' : '快速版'}${entry['pinned'] == true ? ' · 已置顶' : ''}${state['interrupted'] == true ? ' · 已中断' : ''}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      onTap: busy
                                          ? null
                                          : () {
                                              _historyTimer?.cancel();
                                              _historyRestoring = true;
                                              final backup = _snapshot();
                                              try {
                                                setState(() {
                                                  _restoreSnapshot(state);
                                                  _sessionId =
                                                      entry['id'] as String;
                                                });
                                                Navigator.pop(dialogContext);
                                              } catch (_) {
                                                _restoreSnapshot(backup);
                                                _historyNotice(
                                                  '这条记录无法恢复，其他记录不受影响。',
                                                );
                                              } finally {
                                                _historyRestoring = false;
                                              }
                                            },
                                      trailing: PopupMenuButton<String>(
                                        tooltip: '管理会话',
                                        icon: const Icon(
                                          Icons.more_horiz,
                                          size: 20,
                                        ),
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'pinned',
                                            child: Text(
                                              entry['pinned'] == true
                                                  ? '取消置顶'
                                                  : '置顶',
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'archived',
                                            child: Text(
                                              archived ? '取消归档' : '归档',
                                            ),
                                          ),
                                        ],
                                        onSelected: (key) {
                                          final previous = entry[key];
                                          entry[key] = entry[key] != true;
                                          if (!_writeHistory()) {
                                            entry[key] = previous;
                                          }
                                          update(() {});
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          '仅保存在当前浏览器 · 归档不会删除错题',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
