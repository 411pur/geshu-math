import 'package:flutter/material.dart';

import '../../../shared/widgets/styled_markdown.dart';

/// 生成讲解前的题干素材卡。
///
/// 默认把从错题或 OCR 带来的 LaTeX 展示成可读数学预览；只有用户主动点
/// 「编辑题干」时才显示可编辑的原始文本，避免输入框直接暴露反斜杠公式。
class LessonTextInputCard extends StatelessWidget {
  final TextEditingController controller;
  final bool previewing;
  final VoidCallback onEdit;
  final VoidCallback onDone;
  final ValueChanged<String> onChanged;

  const LessonTextInputCard({
    super.key,
    required this.controller,
    required this.previewing,
    required this.onEdit,
    required this.onDone,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = controller.text.trim().isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.article_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    previewing ? '题目预览' : '题干输入',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (previewing)
                  TextButton.icon(
                    key: const ValueKey('lesson-text-edit'),
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('编辑题干'),
                  )
                else
                  TextButton.icon(
                    key: const ValueKey('lesson-text-done'),
                    onPressed: hasText ? onDone : null,
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('完成编辑'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (previewing)
              Container(
                key: const ValueKey('lesson-text-preview'),
                constraints: const BoxConstraints(minHeight: 120),
                alignment: Alignment.topLeft,
                child: hasText
                    ? StyledMarkdown(
                        data: controller.text,
                        fontSize: 15,
                        selectable: false,
                      )
                    : Text(
                        '尚未填写题干',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              )
            else ...[
              TextField(
                key: const ValueKey('lesson-text-input'),
                controller: controller,
                minLines: 4,
                maxLines: 10,
                onChanged: onChanged,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '粘贴或输入题目；支持 LaTeX 公式',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '可以粘贴 LaTeX；完成后点击「完成编辑」查看数学排版预览。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
