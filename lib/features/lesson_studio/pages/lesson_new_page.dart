import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/legacy_lesson_bridge.dart';
import '../data/lesson_document.dart';
import '../data/lesson_providers.dart';
import '../models/lesson_contracts.dart';
import 'lesson_generate_page.dart';

/// 「不扫错题也能生成讲解」的入口页：文本 / 图片 / 文档三种素材任意组合。
///
/// 这里只负责收集素材：拼出 [LessonGenerationInput] 后跳 [LessonGeneratePage]，
/// 进度、播放、下载都复用那一套，两个入口不会有第二份实现。
class LessonNewPage extends ConsumerStatefulWidget {
  final String initialText;
  const LessonNewPage({super.key, this.initialText = ''});

  @override
  ConsumerState<LessonNewPage> createState() => _LessonNewPageState();
}

class _LessonNewPageState extends ConsumerState<LessonNewPage> {
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  Uint8List? _imageBytes;
  String _imageMime = 'image/jpeg';
  String _imageName = '题目图片';
  LessonDocumentDraft? _document;
  bool _readingDocument = false;
  String? _notice;

  String? get _imageDataUrl => _imageBytes == null
      ? null
      : 'data:$_imageMime;base64,${base64Encode(_imageBytes!)}';

  bool get _hasMaterial =>
      _textController.text.trim().isNotEmpty ||
      _imageBytes != null ||
      (_document?.chars ?? 0) > 0;

  @override
  void initState() { super.initState(); _textController.text = widget.initialText; }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  static String _mimeForImage(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageMime = _mimeForImage(picked.name);
        _imageName = picked.name;
        _notice = null;
      });
    } catch (error) {
      if (mounted) setState(() => _notice = '图片读取失败：$error');
    }
  }

  Future<void> _pickDocument() async {
    setState(() {
      _readingDocument = true;
      _notice = null;
    });
    try {
      final picked = await pickLessonDocument();
      if (picked == null) return;
      final kind = lessonDocumentKindOf(picked.fileName);
      if (kind == null) {
        setState(() => _notice = '只支持 PDF、Word（.docx）与纯文本（txt/md/csv）');
        return;
      }
      final text = kind == LessonDocumentKind.text
          ? decodePlainText(picked.bytes)
          : await ref
                .read(lessonBridgeProvider)
                .extractDocument(
                  fileName: picked.fileName,
                  bytes: picked.bytes,
                );
      if (!mounted) return;
      setState(() {
        _document = LessonDocumentDraft(
          fileName: picked.fileName,
          kind: kind,
          text: text,
          byteLength: picked.bytes.length,
        );
        if (text.trim().isEmpty) {
          _notice = '没有从文件里读到文字：扫描件或纯图片 PDF 请改用「上传图片」';
        }
      });
    } on LessonBridgeException catch (error) {
      if (mounted) setState(() => _notice = error.message);
    } catch (error) {
      if (mounted) setState(() => _notice = '文档解析失败：$error');
    } finally {
      if (mounted) setState(() => _readingDocument = false);
    }
  }

  Future<void> _generate() async {
    final input = mergeLessonMaterial(
      typedText: _textController.text,
      imageDataUrl: _imageDataUrl,
      documentText: _document?.text,
    );
    if (!input.hasMaterial) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LessonGeneratePage(input: input, autoStart: true),
      ),
    );
    if (!mounted) return;
    ref.invalidate(lessonLibraryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('生成数学讲解')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: TextField(
                controller: _textController,
                minLines: 4,
                maxLines: 10,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('上传图片'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _readingDocument ? null : _pickDocument,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(_readingDocument ? '正在解析…' : '上传文档'),
                ),
              ),
            ],
          ),
          if (_imageBytes != null) ...[
            const SizedBox(height: 12),
            _AttachmentTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _imageBytes!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined),
                ),
              ),
              title: _imageName,
              subtitle: formatDocumentSize(_imageBytes!.length),
              onRemove: () => setState(() {
                _imageBytes = null;
                _imageName = '题目图片';
              }),
            ),
          ],
          if (_document != null) ...[
            const SizedBox(height: 12),
            _AttachmentTile(
              leading: const Icon(Icons.description_outlined, size: 28),
              title: _document!.fileName,
              subtitle: '已取到 ${_document!.chars} 字 · ${formatDocumentSize(_document!.byteLength)}',
              onRemove: () => setState(() => _document = null),
            ),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _notice!,
                    style: TextStyle(color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _hasMaterial ? _generate : null,
            icon: const Icon(Icons.smart_display_outlined),
            label: const Text('生成数学讲解'),
          ),
          const SizedBox(height: 8),
          Text(
            '生成需要几分钟，页面会显示读题、求解、排课和视觉检查的进度；完成后可以直接播放，也可以下载单文件 HTML 发给学生。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 已选素材的横条：图标/缩略图 + 名称 + 说明 + 移除。
class _AttachmentTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onRemove;

  const _AttachmentTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: SizedBox(width: 44, height: 44, child: Center(child: leading)),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '移除',
          onPressed: onRemove,
        ),
      ),
    );
  }
}
