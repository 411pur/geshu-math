import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/lesson_providers.dart';
import '../models/lesson_project.dart';
import 'lesson_player_page.dart';

class LessonLibraryPage extends ConsumerWidget {
  const LessonLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lessonLibraryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('互动讲解')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('读取失败：$e')),
        data: (items) => items.isEmpty
            ? const Center(
                child: Text(
                  '还没有互动讲解\n从错题指导或扫描识题生成',
                  textAlign: TextAlign.center,
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(lessonLibraryProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) => _card(context, ref, items[index]),
                ),
              ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    LessonProjectRecord record,
  ) {
    final color = record.status == LessonProjectStatus.done
        ? Colors.green
        : record.status == LessonProjectStatus.warning
        ? Colors.orange
        : record.status == LessonProjectStatus.failed
        ? Colors.red
        : Colors.blue;
    return Card(
      child: ListTile(
        leading: Icon(
          record.hasHtml ? Icons.smart_display : Icons.error_outline,
          color: color,
        ),
        title: Text(record.title),
        subtitle: Text(
          '${record.subject.isEmpty ? '物理' : record.subject} · ${record.message}\n${record.visualWarnings.isNotEmpty ? '视觉提示：${record.visualWarnings.first}' : '生成时间：${record.updatedAt.toString().substring(0, 16)}'}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            // 每个分支只 await 一次，且 await 之后不再触碰 BuildContext，
            // 避免「跨 async gap 使用 context」的隐患。
            if (value == 'open') {
              await _open(context, ref, record);
            } else if (value == 'delete') {
              await _delete(context, ref, record);
            }
          },
          itemBuilder: (_) => [
            if (record.hasHtml)
              const PopupMenuItem(value: 'open', child: Text('打开讲解')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: record.hasHtml ? () => _open(context, ref, record) : null,
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    LessonProjectRecord record,
  ) async {
    final htmlText = await ref
        .read(lessonRepositoryProvider)
        .loadHtml(record.id);
    if (!context.mounted || htmlText == null || htmlText.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LessonPlayerPage(htmlText: htmlText, title: record.title),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    LessonProjectRecord record,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除互动讲解'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(lessonRepositoryProvider).delete(record.id);
    ref.invalidate(lessonLibraryProvider);
  }
}
