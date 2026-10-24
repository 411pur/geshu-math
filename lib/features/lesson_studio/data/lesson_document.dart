import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../models/lesson_contracts.dart';

/// 讲解素材里的文档类型。
///
/// 纯文本在本地解码（不发网络请求），PDF / Word 交给引擎取文（Node 侧有 pdf.js 与 mammoth，
/// 许可都是宽松许可；Flutter Web 侧没有等价且许可干净的实现）。
enum LessonDocumentKind { pdf, docx, text }

/// 文件选择器允许的扩展名，与引擎 `POST /api/extract-text` 的支持范围保持一致。
const List<String> lessonDocumentExtensions = ['pdf', 'docx', 'txt', 'md', 'csv'];

const Set<String> _plainTextExtensions = {
  'txt',
  'md',
  'markdown',
  'csv',
  'log',
  'json',
  'yml',
  'yaml',
};

/// 按扩展名判断文档类型；返回 null 表示不支持（调用方给出可执行的提示）。
LessonDocumentKind? lessonDocumentKindOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  final extension = fileName.substring(dot + 1).toLowerCase();
  if (extension == 'pdf') return LessonDocumentKind.pdf;
  if (extension == 'docx') return LessonDocumentKind.docx;
  if (_plainTextExtensions.contains(extension)) return LessonDocumentKind.text;
  return null;
}

/// 纯文本按 UTF-8 解码；allowMalformed 让老式 GBK 文档不至于整页失败（坏字节变 …）。
String decodePlainText(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: true);

/// 文件大小给人看的形式（1 位小数的 MB / 整数 KB）。
String formatDocumentSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).round()} KB';
}

/// 已经取到文字的文档：名称、类型、正文与原始大小。
class LessonDocumentDraft {
  final String fileName;
  final LessonDocumentKind kind;
  final String text;
  final int byteLength;

  const LessonDocumentDraft({
    required this.fileName,
    required this.kind,
    required this.text,
    required this.byteLength,
  });

  int get chars => text.trim().length;

  String get summary => '$fileName · $chars 字 · ${formatDocumentSize(byteLength)}';
}

/// 把「文档取到的文字 + 手打/粘贴的文字 + 图片」合并成一次生成所需的素材。
///
/// 文档文字排在前面：文档里通常就是完整题干，学生手打的更多是补充说明。
LessonGenerationInput mergeLessonMaterial({
  required String typedText,
  String? imageDataUrl,
  String? documentText,
}) {
  final parts = [documentText?.trim() ?? '', typedText.trim()]
      .where((part) => part.isNotEmpty)
      .toList();
  return LessonGenerationInput(
    questionText: parts.join('\n\n'),
    imageDataUrl: imageDataUrl ?? '',
  );
}

/// 系统文件选择器的返回值：只给原始字节，是否解析由调用方决定（便于单测绕过选择器）。
class PickedLessonDocument {
  final String fileName;
  final Uint8List bytes;

  const PickedLessonDocument({required this.fileName, required this.bytes});
}

/// 弹出系统文件选择器，只允许题目标题常用的文档格式。
Future<PickedLessonDocument?> pickLessonDocument() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: lessonDocumentExtensions,
  );
  if (file == null) return null;
  return PickedLessonDocument(
    fileName: file.name,
    bytes: await file.readAsBytes(),
  );
}
