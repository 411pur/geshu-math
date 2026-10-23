import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/entities/wrong_question_entity.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/pdf/pdf_exporter.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../providers/wrong_question_providers.dart';
import '../widgets/wrong_question_delete_dialog.dart';
import '../../lesson_studio/data/lesson_providers.dart';
import '../../lesson_studio/models/lesson_contracts.dart';
import '../../lesson_studio/pages/lesson_generate_page.dart';
import '../../lesson_studio/pages/lesson_player_page.dart';
import '../../../data/database/db_provider.dart';
import 'wrong_question_detail_page.dart';

class WrongQuestionListPage extends ConsumerStatefulWidget {
  const WrongQuestionListPage({super.key});
  @override
  ConsumerState<WrongQuestionListPage> createState() =>
      _WrongQuestionListPageState();
}

class _WrongQuestionListPageState extends ConsumerState<WrongQuestionListPage> {
  String? _filterSubject;
  int? _filterDifficulty, _filterMastery;
  int _sortBy = 0;
  bool _showFavorites = false;

  List<WrongQuestion> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // DataStore 已在 main() 完成初始化并同步注入（见 db_provider.dart），
      // 这里不再需要 await；保留一次读取确保数据源被正确构造。
      ref.read(dataStoreProvider);
      if (!mounted) return;
      final repo = ref.read(wrongQuestionRepositoryProvider);
      final list = await repo.getList(limit: 500, offset: 0);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<WrongQuestion> get _filtered {
    var r = _items.toList();
    if (_showFavorites) r = r.where((x) => x.isFavorited).toList();
    if (_filterSubject != null) {
      r = r.where((x) => x.topic == _filterSubject).toList();
    }
    if (_filterDifficulty != null) {
      r = r.where((x) => x.difficultyLevel == _filterDifficulty).toList();
    }
    if (_filterMastery != null) {
      r = r.where((x) => x.mastery == _filterMastery).toList();
    }
    if (_sortBy == 0) r.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_sortBy == 1) r.sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
    if (_sortBy == 2) {
      r.sort((a, b) => b.difficultyLevel.compareTo(a.difficultyLevel));
    }
    return r;
  }

  int get _unmastered => _items.where((x) => x.mastery == 0).length;
  int get _thisWeek => _items
      .where(
        (x) => x.createdAt > DateTime.now().millisecondsSinceEpoch - 604800000,
      )
      .length;
  int get _favorited => _items.where((x) => x.isFavorited).length;

  void _showPrintSheet() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PrintSheet(
      items: _filtered,
      onPrinted: (id) {
        ref.read(wrongQuestionRepositoryProvider).markPrinted(id);
        _load();
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final f = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('错题本'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/wrong-question/chat'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: '打印',
            onPressed: _showPrintSheet,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilter,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '加载失败: $_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : f.isEmpty
          ? const EmptyStateWidget(message: '暂无错题')
          : Column(
              children: [
                _statsBar(),
                const SizedBox(height: 4),
                _sortBar(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: f.length,
                    itemBuilder: (_, i) =>
                        AppReveal(index: i, child: _card(context, f[i])),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statsBar() => Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat('总错题', _items.length, AppColors.mutedForeground),
            _stat('本周新增', _thisWeek, AppColors.accent),
            _stat('未掌握', _unmastered, AppColors.error),
            _stat('收藏', _favorited, AppColors.warning),
          ],
        ),
        const SizedBox(height: 12),
        _segmentedControl(),
      ],
    ),
  );

  Widget _segmentedControl() => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: AppColors.secondarySystem,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        Expanded(
          child: _tabBtn(
            '全部错题',
            !_showFavorites,
            () => setState(() => _showFavorites = false),
          ),
        ),
        Expanded(
          child: _tabBtn(
            '收藏夹',
            _showFavorites,
            () => setState(() => _showFavorites = true),
          ),
        ),
      ],
    ),
  );

  Widget _tabBtn(String label, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active
                    ? AppColors.foreground
                    : AppColors.mutedForeground,
              ),
            ),
          ),
        ),
      );

  Widget _stat(String l, int v, Color c) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$v',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c),
      ),
      const SizedBox(height: 2),
      Text(
        l,
        style: const TextStyle(fontSize: 11, color: AppColors.mutedForeground),
      ),
    ],
  );

  Widget _sortBar() {
    final labels = ['最近', '最多错', '难度'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: List.generate(3, (i) {
          final sel = _sortBy == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _sortBy = i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: sel
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                    color: sel ? AppColors.primary : AppColors.mutedForeground,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _card(BuildContext context, WrongQuestion item) {
    final c = item.topic != null
        ? AppColors.forSubject(item.topic!)
        : AppColors.primary;
    return Dismissible(
      key: Key('${item.id ?? 0}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmAndDelete(item),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: item.id != null
              ? () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WrongQuestionDetailPage(
                        item: item,
                        onMasteryChanged: (mastery) async {
                          await ref
                              .read(wrongQuestionRepositoryProvider)
                              .updateMastery(item.id!, mastery);
                          _load();
                        },
                        onFavoritedChanged: (fav) async {
                          await ref
                              .read(wrongQuestionRepositoryProvider)
                              .toggleFavorite(item.id!);
                          _load();
                        },
                        onTagsChanged: (tags) async {
                          await ref
                              .read(wrongQuestionRepositoryProvider)
                              .updateTags(item.id!, tags);
                          _load();
                        },
                        onDeleted: () async {
                          await ref
                              .read(wrongQuestionRepositoryProvider)
                              .delete(item.id!);
                          _load();
                        },
                      ),
                    ),
                  );
                  _load();
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '${item.difficultyLevel}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: c),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.questionText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          if (item.isFavorited)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.star,
                                size: 16,
                                color: AppColors.warning,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${item.topic ?? ""} · ${item.subTopic ?? ""}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.mutedForeground,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () async {
                              final n = (item.mastery + 1) % 3;
                              await ref
                                  .read(wrongQuestionRepositoryProvider)
                                  .updateMastery(item.id!, n);
                              _load();
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _mc[item.mastery],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _ml[item.mastery],
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _mc[item.mastery],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _hasLessonMaterial(item)
                          ? '生成或播放数学讲解'
                          : '缺少题目图片和题干',
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      onPressed: _hasLessonMaterial(item)
                          ? () => _openInteractiveLesson(item)
                          : null,
                      icon: const Icon(Icons.smart_display_outlined),
                    ),
                    IconButton(
                      tooltip: '删除错题',
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      color: AppColors.error,
                      onPressed: () => _confirmAndDelete(item),
                      icon: const Icon(Icons.delete_outline),
                    ),
                    GestureDetector(
                      onTap: () async {
                        await ref
                            .read(wrongQuestionRepositoryProvider)
                            .toggleFavorite(item.id!);
                        _load();
                      },
                      child: Icon(
                        item.isFavorited ? Icons.star : Icons.star_border,
                        size: 22,
                        color: item.isFavorited
                            ? AppColors.warning
                            : AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final _mc = [AppColors.error, AppColors.warning, AppColors.accent];
  final _ml = ['未掌握', '复习中', '已掌握'];

  bool _hasLessonMaterial(WrongQuestion item) =>
      (item.questionImagePath?.trim().isNotEmpty ?? false) ||
      item.questionText.trim().isNotEmpty;

  Future<void> _openInteractiveLesson(WrongQuestion item) async {
    final id = item.id;
    if (id == null) return;
    final image = item.questionImagePath?.trim() ?? '';
    if (image.isEmpty && item.questionText.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这道错题缺少题目图片和题干，无法生成讲解')));
      return;
    }
    try {
      final repository = ref.read(lessonRepositoryProvider);
      final latest = await repository.latestForRef(id, 'wrongQuestion');
      if (!mounted) return;
      if (latest?.hasHtml == true) {
        final htmlText = await repository.loadHtml(latest!.id);
        if (!mounted) return;
        if (htmlText != null && htmlText.isNotEmpty) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  LessonPlayerPage(htmlText: htmlText, title: latest.title),
            ),
          );
          return;
        }
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LessonGeneratePage(
            input: LessonGenerationInput(
              imageDataUrl: image,
              questionText: item.questionText,
              refId: id,
              refKind: 'wrongQuestion',
            ),
          ),
        ),
      );
      ref.invalidate(lessonLibraryProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开数学讲解失败：$error')));
      }
    }
  }

  Future<bool> _confirmAndDelete(WrongQuestion item) async {
    final id = item.id;
    if (id == null) return false;
    final confirmed = await confirmWrongQuestionDeletion(context);
    if (!confirmed) return false;
    try {
      await ref.read(wrongQuestionRepositoryProvider).delete(id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已删除错题')));
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
      return false;
    }
  }

  void _showFilter() {
    final topics =
        _items
            .map((e) => e.topic)
            .whereType<String>()
            .where((t) => t.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('筛选', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            if (topics.isNotEmpty) ...[
              _fs(
                '模块',
                ['全部', ...topics],
                _filterSubject,
                (v) => setState(() => _filterSubject = v == '全部' ? null : v),
              ),
              const SizedBox(height: 12),
            ],
            _fs(
              '掌握度',
              ['全部', '未掌握', '复习中', '已掌握'],
              _filterMastery,
              (v) => setState(() {
                final m = {'全部': null, '未掌握': 0, '复习中': 1, '已掌握': 2};
                _filterMastery = m[v];
              }),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fs(String t, List<String> o, dynamic c, void Function(String) s) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: o.map((x) {
              bool sel;
              if (c is int?) {
                sel = {'全部': null, '未掌握': 0, '复习中': 1, '已掌握': 2}[x] == c;
              } else {
                sel = x == '全部' ? c == null : x == c;
              }
              return FilterChip(
                label: Text(x, style: const TextStyle(fontSize: 12)),
                selected: sel,
                onSelected: (_) => s(x),
              );
            }).toList(),
          ),
        ],
      );
}

class _PrintSheet extends StatefulWidget {
  final List<WrongQuestion> items;
  final void Function(int id) onPrinted;
  const _PrintSheet({required this.items, required this.onPrinted});
  @override
  State<_PrintSheet> createState() => _PrintSheetState();
}

class _PrintSheetState extends State<_PrintSheet> {
  final _sel = <int>{};
  final _ana = <int>{};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final sorted = List<WrongQuestion>.from(widget.items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 16),
              Text(
                '选择打印 (${_sel.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (_sel.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _sel.clear();
                    _ana.clear();
                  }),
                  child: const Text('全消'),
                ),
              const SizedBox(width: 8),
            ],
          ),
          const Divider(),
          Expanded(
            child: sorted.isEmpty
                ? const Center(child: Text('暂无错题'))
                : ListView.builder(
                    itemCount: sorted.length,
                    itemBuilder: (_, i) {
                      final item = sorted[i];
                      final id = item.id ?? 0;
                      final on = _sel.contains(id);
                      return ListTile(
                        leading: Checkbox(
                          value: on,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _sel.add(id);
                              _ana.add(id);
                            } else {
                              _sel.remove(id);
                              _ana.remove(id);
                            }
                          }),
                        ),
                        title: Text(
                          item.questionText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Row(
                          children: [
                            Text(
                              item.topic ?? '',
                              style: const TextStyle(fontSize: 11),
                            ),
                            if (item.printedAt > 0)
                              const Text(
                                ' · 已打印',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green,
                                ),
                              ),
                          ],
                        ),
                        trailing: on
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '解析',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  Switch(
                                    value: _ana.contains(id),
                                    onChanged: (v) => setState(() {
                                      if (v) {
                                        _ana.add(id);
                                      } else {
                                        _ana.remove(id);
                                      }
                                    }),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ],
                              )
                            : null,
                        onTap: () => setState(() {
                          if (on) {
                            _sel.remove(id);
                            _ana.remove(id);
                          } else {
                            _sel.add(id);
                            _ana.add(id);
                          }
                        }),
                      );
                    },
                  ),
          ),
          if (_sel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  label: const Text('生成PDF'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    final toPrint = widget.items
        .where((x) => _sel.contains(x.id ?? 0))
        .toList();
    try {
      final bytes = await PdfExporter.wrongQuestions(
        toPrint,
        withAnalysisIds: _ana,
      );
      await PdfExporter.sharePdf(
        '错题本_${DateTime.now().month}月${DateTime.now().day}日',
        bytes,
      );
      for (final item in toPrint) {
        if (item.id != null) widget.onPrinted(item.id!);
      }
    } finally {
      setState(() => _busy = false);
      if (mounted) Navigator.pop(context);
    }
  }
}
