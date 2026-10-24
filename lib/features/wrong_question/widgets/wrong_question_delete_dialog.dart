import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

Future<bool> confirmWrongQuestionDeletion(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('确认删除'),
      content: const Text('删除后将无法恢复，确定要删除这道错题吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
