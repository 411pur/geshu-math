import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_display_widget.dart';

class ExamAnalysisPage extends ConsumerStatefulWidget {
  const ExamAnalysisPage({super.key});
  @override
  ConsumerState<ExamAnalysisPage> createState() => _ExamAnalysisPageState();
}

class _ExamAnalysisPageState extends ConsumerState<ExamAnalysisPage> {
  XFile? _image;
  String? _ocrText, _error;
  bool _loading = false, _analyzing = false;
  final _picker = ImagePicker();

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
    final image = await _picker.pickImage(source: source, imageQuality: 80);
    if (image != null) {
      setState(() {
        _image = image;
        _ocrText = null;
        _error = null;
      });
      _runOcr();
    }
  }

  Future<void> _runOcr() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      _loading = false;
      _ocrText = 'OCR识别结果：\n本次月考数学卷，满分150分，得分108分。\n第1题：函数-二次函数的最值（5分/得3分）...';
    });
  }

  Future<void> _analyze() async {
    setState(() => _analyzing = true);
    await Future.delayed(const Duration(seconds: 3));
    setState(() => _analyzing = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('考试分析')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _uploadSection(),
          const SizedBox(height: 24),
          if (_image == null && !_loading) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.6),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 18, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text(
                        '怎么用',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '上传试卷照片后，AI 会识别题干、按模块统计得分情况，'
                    '并给出下一步复习建议。也可以从「考情历史」查看往次记录。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_loading)
            const LoadingIndicator(message: '正在识别文字...')
          else if (_error != null)
            ErrorDisplayWidget(message: _error!, onRetry: _pickImage)
          else if (_ocrText != null) ...[
            _ocrResult(),
            const SizedBox(height: 16),
            _analyzing
                ? const LoadingIndicator(message: 'AI正在分析...')
                : AppPressScale(
                    pressedScale: 0.864,
                    child: FilledButton.icon(
                      onPressed: _analyze,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('开始AI分析'),
                    ),
                  ),
          ],
          if (!_analyzing && _ocrText != null) ...[
            const SizedBox(height: 24),
            _analysisResult(),
          ],
        ],
      ),
    ),
  );

  Widget _uploadSection() => _image != null
      ? Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                _image!.path,
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
                    onPressed: () => setState(() {
                      _image = null;
                      _ocrText = null;
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

  Widget _ocrResult() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_snippet, size: 18),
              const SizedBox(width: 8),
              Text('识别结果', style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(_ocrText!, style: const TextStyle(fontSize: 13)),
        ],
      ),
    ),
  );

  Widget _analysisResult() => Container(
    padding: const EdgeInsets.all(16),
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('AI分析报告', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        const Text('总体评价：本次月考函数与导数得分率65%，平面几何82%，概率统计90%...'),
        const SizedBox(height: 12),
        const Text('优势：平面几何证明、概率计算', style: TextStyle(color: AppColors.accent)),
        const Text(
          '薄弱：导数与单调性(65%)、圆锥曲线综合(58%)',
          style: TextStyle(color: AppColors.error),
        ),
        const SizedBox(height: 16),
        FilledButton.tonal(onPressed: () {}, child: const Text('查看详细分析')),
      ],
    ),
  );
}
