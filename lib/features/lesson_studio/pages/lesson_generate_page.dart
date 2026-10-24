import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/lesson_providers.dart';
import '../models/lesson_contracts.dart';
import '../models/lesson_project.dart';
import 'lesson_player_page.dart';

class LessonGeneratePage extends ConsumerStatefulWidget {
  final LessonGenerationInput input;

  /// 从「生成数学讲解」入口进来时直接开跑，不用再点一次按钮。
  final bool autoStart;

  const LessonGeneratePage({
    super.key,
    required this.input,
    this.autoStart = false,
  });

  @override
  ConsumerState<LessonGeneratePage> createState() => _LessonGeneratePageState();
}

class _LessonGeneratePageState extends ConsumerState<LessonGeneratePage> {
  LessonProjectRecord? _record;
  LessonProgressEvent? _event;
  bool _started = false;

  bool get _running =>
      _record == null ||
      _record!.status == LessonProjectStatus.queued ||
      _record!.status == LessonProjectStatus.running;

  bool get _done =>
      _record?.hasHtml == true &&
      (_record!.status == LessonProjectStatus.done ||
          _record!.status == LessonProjectStatus.warning);

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    setState(() {
      _record = null;
      _event = const LessonProgressEvent(
        stage: LessonProjectStage.extracting,
        progress: 2,
        message: '正在提交到数学讲解生成服务',
      );
    });
    final record = await ref
        .read(lessonRepositoryProvider)
        .create(
          widget.input,
          onProgress: (event) {
            if (mounted) setState(() => _event = event);
          },
        );
    if (!mounted) return;
    setState(() => _record = record);
    ref.invalidate(lessonLibraryProvider);
  }

  Future<void> _preview() async {
    final record = _record;
    if (record == null || !record.hasHtml) return;
    final htmlText = await ref
        .read(lessonRepositoryProvider)
        .loadHtml(record.id);
    if (!mounted || htmlText == null || htmlText.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LessonPlayerPage(htmlText: htmlText, title: record.title),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeImage(widget.input.imageDataUrl);
    final record = _record;
    final event = _event;
    return Scaffold(
      appBar: AppBar(title: const Text('生成互动讲解')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (bytes != null) ...[
            const Text(
              '题目图片',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Image.memory(
                bytes,
                height: 280,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 220,
                  child: Center(child: Text('图片读取失败')),
                ),
              ),
            ),
          ] else ...[
            // 纯文字题（手打或来自文档）：把题干显示出来，别只留一个读不出来的图片框。
            const Text(
              '题目文字',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.input.questionText.trim().isEmpty
                      ? '没有题目素材'
                      : widget.input.questionText.trim(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (!_started)
            FilledButton.icon(
              onPressed: widget.input.hasMaterial ? _start : null,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('开始生成讲解'),
            ),
          if (_started) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_running)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            event?.message ?? record?.message ?? '等待数学讲解服务',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    LinearProgressIndicator(
                      value: ((event?.progress ?? record?.progress ?? 0) / 100)
                          .clamp(0, 1),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '阶段：${_stageLabel(event?.stage ?? record?.stage ?? LessonProjectStage.queued)}',
                    ),
                    if ((record?.visualWarnings ?? const []).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '视觉提示：${record!.visualWarnings.first}',
                        style: TextStyle(color: Colors.orange.shade800),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (record?.status == LessonProjectStatus.failed) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '生成已停止',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(record!.error),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        _started = false;
                        _start();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新生成'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_done) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _preview,
              icon: const Icon(Icons.smart_display),
              label: const Text('打开互动讲解'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _preview,
              icon: const Icon(Icons.download),
              label: const Text('预览并下载单文件 HTML'),
            ),
          ],
        ],
      ),
    );
  }

  static Uint8List? _decodeImage(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    if (comma <= 0) return null;
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  static String _stageLabel(LessonProjectStage stage) => switch (stage) {
    LessonProjectStage.queued => '排队',
    LessonProjectStage.extracting => '识别题目',
    LessonProjectStage.solving => '独立求解',
    LessonProjectStage.verifying => '内容复核',
    LessonProjectStage.planning => '讲解排课',
    LessonProjectStage.rendering => '生成黑板',
    LessonProjectStage.visualCheck => '视觉检查',
    LessonProjectStage.repairing => '自动修复',
    LessonProjectStage.done => '完成',
    LessonProjectStage.failed => '失败',
  };
}
