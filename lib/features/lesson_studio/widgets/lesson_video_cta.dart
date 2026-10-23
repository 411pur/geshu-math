import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../data/lesson_providers.dart';
import '../models/lesson_contracts.dart';
import '../models/lesson_project.dart';
import '../pages/lesson_generate_page.dart';
import '../pages/lesson_player_page.dart';

/// 「还是没听懂？→ 生成数学讲解 / 播放讲解」收尾区（每处题目解析的最下方都用它）。
///
/// 两种状态由这道题自己的讲解记录决定（按 refId + refKind 查本地讲解库）：
/// - 还没生成过：主按钮「生成数学讲解」，有题目图片**或**题干文字就能点；
/// - 已经生成过：「播放讲解」直接播放，旁边留一个「重新生成」。
/// 从生成页返回后会重新查一次，所以生成完按钮当场就变成「播放讲解」，不需要手动刷新。
class LessonVideoCta extends ConsumerStatefulWidget {
  final String imageDataUrl;
  final String questionText;
  final List<String> options;
  final int refId;
  final String refKind;
  final String title;
  final String subtitle;
  final String readyTitle;
  final String readySubtitle;

  const LessonVideoCta({
    super.key,
    this.imageDataUrl = '',
    this.questionText = '',
    this.options = const [],
    this.refId = 0,
    this.refKind = 'wrongQuestion',
    this.title = '还是没听懂？让老师把这道题讲一遍',
    this.subtitle = '生成一段带板书、图形重绘和语音讲解的互动讲解：可以暂停、回看，跟着老师一步步走。',
    this.readyTitle = '这道题的讲解已经生成好了',
    this.readySubtitle = '直接播放，或在「我的 → 互动讲解」里回看；想换一种讲法可以重新生成。',
  });

  @override
  ConsumerState<LessonVideoCta> createState() => _LessonVideoCtaState();
}

class _LessonVideoCtaState extends ConsumerState<LessonVideoCta> {
  LessonProjectRecord? _existing;
  bool _busy = false;

  LessonGenerationInput get _input => LessonGenerationInput(
    imageDataUrl: widget.imageDataUrl,
    questionText: widget.questionText,
    options: widget.options,
    refId: widget.refId,
    refKind: widget.refKind,
  );

  bool get _enabled => _input.hasMaterial;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void didUpdateWidget(LessonVideoCta oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refId != widget.refId ||
        oldWidget.refKind != widget.refKind ||
        oldWidget.questionText != widget.questionText) {
      _loadExisting();
    }
  }

  /// 查这道题有没有已经生成好的讲解（没有 refId 的临时题目就按"未生成"处理）。
  Future<void> _loadExisting() async {
    if (widget.refId <= 0 || widget.refKind.isEmpty) {
      if (mounted && _existing != null) setState(() => _existing = null);
      return;
    }
    try {
      final latest = await ref
          .read(lessonRepositoryProvider)
          .latestForRef(widget.refId, widget.refKind);
      if (!mounted) return;
      setState(() => _existing = (latest != null && latest.hasHtml) ? latest : null);
    } catch (_) {
      if (mounted) setState(() => _existing = null);
    }
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => LessonGeneratePage(input: _input)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    ref.invalidate(lessonLibraryProvider);
    await _loadExisting();
  }

  Future<void> _openExisting() async {
    final record = _existing;
    if (record == null) return;
    setState(() => _busy = true);
    try {
      final html = await ref.read(lessonRepositoryProvider).loadHtml(record.id);
      if (!mounted) return;
      if (html == null || html.isEmpty) {
        // 记录在、文件没了：退回"未生成"，让学生重新生成而不是点开一个空播放器。
        setState(() => _existing = null);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LessonPlayerPage(htmlText: html, title: record.title),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting = _existing != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Text(
          hasExisting ? widget.readyTitle : widget.title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          hasExisting ? widget.readySubtitle : widget.subtitle,
          style: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AppColors.mutedForeground,
          ),
        ),
        const SizedBox(height: 12),
        if (hasExisting)
          Row(
            children: [
              Expanded(
                child: AppPressScale(
                  pressedScale: 0.9,
                  enabled: !_busy,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _openExisting,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('播放讲解'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AppPressScale(
                pressedScale: 0.9,
                enabled: !_busy,
                child: OutlinedButton(
                  onPressed: _busy ? null : _generate,
                  child: const Text('重新生成'),
                ),
              ),
            ],
          )
        else
          AppPressScale(
            pressedScale: 0.9,
            enabled: _enabled && !_busy,
            child: FilledButton.icon(
              onPressed: _enabled && !_busy ? _generate : null,
              icon: const Icon(Icons.smart_display_outlined),
              label: const Text('生成数学讲解'),
            ),
          ),
        if (!hasExisting && !_enabled) ...[
          const SizedBox(height: 6),
          const Text(
            '需要题目图片或题干文字才能生成',
            style: TextStyle(fontSize: 11, color: AppColors.mutedForeground),
          ),
        ],
      ],
    );
  }
}
