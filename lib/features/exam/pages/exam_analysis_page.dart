import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/network/network_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/dify_response_models.dart';
import '../../../data/repositories/exam_repository.dart';
import '../../../shared/widgets/error_display_widget.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../providers/exam_providers.dart';
import '../widgets/exam_analysis_card.dart';

class ExamAnalysisPage extends ConsumerStatefulWidget {
  const ExamAnalysisPage({super.key});

  @override
  ConsumerState<ExamAnalysisPage> createState() => _ExamAnalysisPageState();
}

class _ExamAnalysisPageState extends ConsumerState<ExamAnalysisPage> {
  final _picker = ImagePicker();
  final _ocrController = TextEditingController();
  XFile? _image;
  Uint8List? _imageBytes;
  String _imageMime = 'image/jpeg';
  String? _error;
  AnalysisResult? _analysis;
  bool _loading = false;
  bool _analyzing = false;
  int _streamingChars = 0;
  bool _manualEditing = false;

  @override
  void dispose() {
    _ocrController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await _picker.pickImage(source: source, imageQuality: 85);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _image = image;
      _imageBytes = bytes;
      _imageMime = image.mimeType ?? 'image/jpeg';
      _error = null;
      _analysis = null;
      _manualEditing = false;
      _ocrController.clear();
    });
    await _runOcr();
  }

  Future<void> _runOcr() async {
    final bytes = _imageBytes;
    if (bytes == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base64Image = 'data:$_imageMime;base64,${base64Encode(bytes)}';
      final text = await ref
          .read(aiApiClientProvider)
          .ocrExamPaper(base64Image);
      if (!mounted) return;
      _ocrController.text = text ?? '';
      setState(() {
        if (text == null || text.trim().isEmpty) {
          _error = '未能自动识别试卷文字。请检查图片清晰度，或在下方直接粘贴/修改识别文本。';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '试卷识别失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startManualText() {
    setState(() {
      _error = null;
      _analysis = null;
      _manualEditing = true;
      _ocrController.clear();
    });
  }

  Future<void> _analyze() async {
    final text = _ocrController.text.trim();
    if (text.isEmpty || _analyzing) return;
    setState(() {
      _analyzing = true;
      _error = null;
      _analysis = null;
      _streamingChars = 0;
    });
    try {
      final repository = ref.read(examRepositoryProvider);
      await for (final step in repository.submitExam(
        ocrText: text,
        imagePath: _image?.path,
      )) {
        if (!mounted) return;
        switch (step) {
          case ExamFlowStepLoading():
            break;
          case ExamFlowStepChunk(:final text):
            setState(() => _streamingChars += text.length);
          case ExamFlowStepResult(:final result):
            setState(() => _analysis = result);
            ref.invalidate(examHistoryProvider);
          case ExamFlowStepError(:final message):
            setState(() => _error = message);
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'AI分析失败：$error');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasOcrEditor =
        _manualEditing ||
        _ocrController.text.isNotEmpty ||
        _imageBytes != null ||
        _error != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('考试分析'),
        actions: [
          if (_ocrController.text.trim().isNotEmpty && !_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新识别',
              onPressed: _analyzing ? null : _runOcr,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _uploadSection(),
            const SizedBox(height: 12),
            if (_imageBytes == null && !_loading)
              OutlinedButton.icon(
                onPressed: _startManualText,
                icon: const Icon(Icons.edit_note),
                label: const Text('直接粘贴识别文本'),
              ),
            if (_loading) ...[
              const SizedBox(height: 18),
              const LoadingIndicator(message: '正在识别试卷文字...'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorDisplayWidget(
                message: _error!,
                onRetry: _imageBytes == null ? _startManualText : _runOcr,
              ),
            ],
            if (hasOcrEditor && !_loading) ...[
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.text_snippet, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '识别结果（可编辑）',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('exam-ocr-text'),
                        controller: _ocrController,
                        minLines: 6,
                        maxLines: 14,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: '请粘贴或修正试卷文字、总分、各题得分...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AppPressScale(
                pressedScale: 0.864,
                child: FilledButton.icon(
                  key: const ValueKey('exam-analyze'),
                  onPressed: _analyzing || _ocrController.text.trim().isEmpty
                      ? null
                      : _analyze,
                  icon: _analyzing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _analyzing ? 'AI分析中… 已接收 $_streamingChars 字' : '开始AI分析',
                  ),
                ),
              ),
            ],
            if (_analysis != null) ...[
              const SizedBox(height: 18),
              ExamAnalysisCard(analysis: _analysis!),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => context.go('/exam/history'),
                icon: const Icon(Icons.history),
                label: const Text('查看考情历史'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _uploadSection() => _imageBytes != null
      ? Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                _imageBytes!,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: AppPressScale(
                pressedScale: 0.84,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: '移除试卷图片',
                    onPressed: () => setState(() {
                      _image = null;
                      _imageBytes = null;
                      _manualEditing = false;
                      _ocrController.clear();
                      _analysis = null;
                      _error = null;
                    }),
                  ),
                ),
              ),
            ),
          ],
        )
      : AppPressScale(
          pressedScale: 0.864,
          child: InkWell(
            onTap: _pickImage,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate,
                    size: 48,
                    color: AppColors.mutedForeground,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '拍照或上传试卷照片',
                    style: TextStyle(color: AppColors.mutedForeground),
                  ),
                ],
              ),
            ),
          ),
        );
}
