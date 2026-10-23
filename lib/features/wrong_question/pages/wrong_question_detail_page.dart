import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/wrong_question_entity.dart';

class WrongQuestionDetailPage extends StatefulWidget {
  final WrongQuestion item;
  final void Function(int mastery)? onMasteryChanged;
  final void Function(bool favorited)? onFavoritedChanged;
  final void Function(List<String> tags)? onTagsChanged;
  const WrongQuestionDetailPage({super.key, required this.item, this.onMasteryChanged, this.onFavoritedChanged, this.onTagsChanged});

  @override State<WrongQuestionDetailPage> createState() => _WrongQuestionDetailPageState();
}

class _WrongQuestionDetailPageState extends State<WrongQuestionDetailPage> {
  late int _m;
  late bool _fav;
  late List<String> _tags;
  final _tagController = TextEditingController();

  static const _allTags = ['概念混淆', '计算失误', '审题偏差', '模型误用', '公式错误', '单位错误', '粗心', '其他'];

  @override void initState() {
    super.initState();
    _m = widget.item.mastery;
    _fav = widget.item.isFavorited;
    try {
      final parsed = json.decode(widget.item.tagsJson ?? '[]');
      _tags = List<String>.from(parsed);
    } catch (_) { _tags = []; }
  }

  @override void dispose() { _tagController.dispose(); super.dispose(); }

  static const _ml = ['未掌握', '复习中', '已掌握'];
  static const _mc = [AppColors.error, AppColors.warning, AppColors.accent];
  static const _mi = [Icons.timer_off, Icons.autorenew, Icons.check_circle];

  void _cycleMastery() => setState(() {
    _m = (_m + 1) % 3;
    widget.onMasteryChanged?.call(_m);
  });

  void _toggleFav() => setState(() {
    _fav = !_fav;
    widget.onFavoritedChanged?.call(_fav);
  });

  void _toggleTag(String tag) {
    setState(() {
      if (_tags.contains(tag)) { _tags.remove(tag); } else { _tags.add(tag); }
      widget.onTagsChanged?.call(List.from(_tags));
    });
  }

  /// 解析 guidanceResultJson，提取解析与正确解法（答案）。
  /// 返回 (analysis, correctSolution)。
  (String, String) _parseGuidance() {
    final raw = widget.item.guidanceResultJson;
    if (raw == null || raw.isEmpty) return ('', '');
    String analysis = '', solution = '';
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      // 兼容两种结构：{analysis:...} 或 {guidance_result:{analysis:...,correct_solution:...}}
      final gr = (map['guidance_result'] is Map) ? map['guidance_result'] as Map<String, dynamic> : map;
      final a = gr['analysis'];
      final s = gr['correct_solution'];
      if (a is String) analysis = a;
      if (s is String) solution = s;
    } catch (_) {
      return (raw, '');
    }
    return (analysis, solution);
  }

  void _addCustomTag() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('添加自定义标签'),
      content: TextField(controller: _tagController, decoration: const InputDecoration(hintText: '输入标签名'), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () {
          final t = _tagController.text.trim();
          if (t.isNotEmpty && !_tags.contains(t)) {
            setState(() { _tags.add(t); widget.onTagsChanged?.call(List.from(_tags)); });
          }
          _tagController.clear();
          Navigator.pop(ctx);
        }, child: const Text('添加')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('错题详情'),
      actions: [
        IconButton(
          icon: Icon(_fav ? Icons.star : Icons.star_border, color: _fav ? Colors.amber : null),
          tooltip: _fav ? '取消收藏' : '收藏',
          onPressed: _toggleFav,
        ),
      ],
    ),
    body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('题目', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(widget.item.questionText),
        if (widget.item.questionImagePath != null && widget.item.questionImagePath!.isNotEmpty) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              base64Decode(widget.item.questionImagePath!.split(',').last),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ],
      ]))),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (widget.item.topic != null) Chip(label: Text(widget.item.topic!)),
        if (widget.item.subTopic != null) Chip(label: Text(widget.item.subTopic!)),
        Chip(label: Text('难度: ${"★" * widget.item.difficultyLevel}')),
      ]),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('标签', style: Theme.of(context).textTheme.titleMedium),
        TextButton.icon(icon: const Icon(Icons.edit, size: 16), label: const Text('编辑'), onPressed: _addCustomTag),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final tag in _allTags)
          FilterChip(
            label: Text(tag, style: TextStyle(fontSize: 12, color: _tags.contains(tag) ? AppColors.primary : AppColors.mutedForeground)),
            selected: _tags.contains(tag),
            selectedColor: AppColors.primary.withValues(alpha: 0.12),
            onSelected: (_) => _toggleTag(tag),
          ),
        if (_tags.where((t) => !_allTags.contains(t)).isNotEmpty) ...[
          const Divider(height: 16),
          for (final tag in _tags.where((t) => !_allTags.contains(t)))
            Chip(
              label: Text(tag, style: const TextStyle(fontSize: 12)),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () => _toggleTag(tag),
            ),
        ],
      ]),
      if (widget.item.guidanceResultJson != null && widget.item.guidanceResultJson!.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('AI指导', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final (analysis, solution) = _parseGuidance();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (analysis.isNotEmpty) ...[
                Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('解析', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  Text(analysis, style: const TextStyle(color: AppColors.mutedForeground)),
                ]))),
                const SizedBox(height: 8),
              ],
              if (solution.isNotEmpty) ...[
                Card(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('答案', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(solution, style: const TextStyle(color: AppColors.foreground)),
                  ])),
                ),
              ],
            ],
          );
        }),
      ],
      const SizedBox(height: 32),
      Text('掌握程度', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _cycleMastery,
          icon: Icon(_mi[_m], color: _mc[_m]),
          label: Text(_ml[_m], style: TextStyle(color: _mc[_m], fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 4),
      const Center(child: Text('点击切换状态', style: TextStyle(fontSize: 11, color: AppColors.mutedForeground))),
    ])),
  );
}
