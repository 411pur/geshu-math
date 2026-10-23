import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/pdf/pdf_exporter.dart';
import '../../../data/datasources/remote/dify_response_models.dart';
import '../../../data/repositories/wrong_question_repository.dart';
import '../../../features/wrong_question/providers/wrong_question_providers.dart';
import '../../../shared/widgets/guidance_analysis_view.dart';
import '../domain/scan_result.dart';
import '../providers/scan_providers.dart';

/// 扫描识题：选图 → 多模态视觉 LLM 识别 → 预览文字与原图，
/// 并可一键获取题目解析模型的分析过程、导出 PDF。
class ScanPreviewPage extends ConsumerStatefulWidget {
  const ScanPreviewPage({super.key});

  @override
  ConsumerState<ScanPreviewPage> createState() => _ScanPreviewPageState();
}

class _ScanPreviewPageState extends ConsumerState<ScanPreviewPage> {
  bool _analyzing = false;
  GuidanceResult? _guidance;
  String? _analysisError;

  /// 拉取题目解析模型的「分析过程」：复用错题诊断工作流（多模态 + 深度推理）。
  /// 工作流会顺带把本次题目自动存入错题本。
  Future<void> _fetchAnalysis(ScanResult result) async {
    setState(() {
      _analyzing = true;
      _analysisError = null;
      _guidance = null;
    });
    try {
      final imageBase64 = result.imageBytes.isNotEmpty
          ? 'data:image/jpeg;base64,${base64Encode(result.imageBytes)}'
          : null;
      final repo = ref.read(wrongQuestionRepositoryProvider);
      await for (final step in repo.submitQuestion(
        questionText: result.recognizedText.isNotEmpty
            ? result.recognizedText
            : '请分析这道题',
        imageBase64: imageBase64,
      )) {
        switch (step) {
          case ResultGuidanceStep(:final result):
            if (mounted) setState(() => _guidance = result);
          case ErrorGuidanceStep(:final message):
            if (mounted) setState(() => _analysisError = message);
          default:
            break;
        }
      }
    } catch (e) {
      if (mounted) setState(() => _analysisError = e.toString());
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }

    if (mounted && _guidance != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已获取题目解析，并自动存入错题本'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => context.go('/wrong-question/list'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanControllerProvider);
    final result = state.value;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('扫描识题'),
        actions: [
          if (result != null) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新识别',
              onPressed: () => ref.read(scanControllerProvider.notifier).scan(),
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: '导出识别 PDF',
              onPressed: () => _exportScanPdf(context, result),
            ),
          ],
        ],
      ),
      body: _buildBody(context, ref, state, result),
      floatingActionButton: result == null
          ? FloatingActionButton.extended(
              onPressed: state.isLoading
                  ? null
                  : () => ref.read(scanControllerProvider.notifier).scan(),
              icon: state.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.photo_library),
              label: Text(state.isLoading ? '识别中…' : '选图识别'),
            )
          : null,
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ScanResult?> state,
    ScanResult? result,
  ) {
    if (state.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在识别题目…'),
          ],
        ),
      );
    }
    if (state.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text('识别失败：${state.error}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(scanControllerProvider.notifier).scan(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (result == null) {
      return const Center(
        child: Text('点击下方按钮，选择题目图片进行识别', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(result.imageBytes),
        ),
        const SizedBox(height: 16),
        const Text(
          '识别文字',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            result.recognizedText.isEmpty
                ? '(未识别出文字，请检查图片清晰度或确认已配置多模态模型 Key)'
                : result.recognizedText,
          ),
        ),
        if (result.options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '已识别 ${result.options.length} 个选项，可直接生成逐选项讲解',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        const SizedBox(height: 16),
        // ── 获取题目解析模型的分析过程 ──
        FilledButton.icon(
          icon: _analyzing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.psychology),
          label: Text(_analyzing ? '解析模型中…' : '获取题目解析（分析过程）'),
          onPressed: _analyzing ? null : () => _fetchAnalysis(result),
        ),
        if (_analysisError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '解析失败：$_analysisError',
                  style: const TextStyle(color: Colors.redAccent),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _fetchAnalysis(result),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        if (_guidance != null) ...[
          const SizedBox(height: 16),
          const Text(
            '题目解析模型的分析过程',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          GuidanceAnalysisView(guidance: _guidance!),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('导出解析 PDF'),
            onPressed: () => _exportGuidancePdf(context),
          ),
        ],
      ],
    );
  }

  Future<void> _exportScanPdf(BuildContext context, ScanResult result) async {
    try {
      final bytes = await PdfExporter.scannedPage(
        title: '扫描识别题目',
        text: result.recognizedText,
        imageBytes: result.imageBytes,
      );
      await PdfExporter.sharePdf('扫描识题', bytes);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _exportGuidancePdf(BuildContext context) async {
    final g = _guidance;
    if (g == null) return;
    try {
      final bytes = await PdfExporter.guidancePdf(g);
      await PdfExporter.sharePdf('题目解析', bytes);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }
}
