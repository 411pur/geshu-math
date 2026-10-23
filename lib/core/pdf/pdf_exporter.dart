import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import '../../data/datasources/remote/dify_response_models.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../domain/entities/wrong_question_entity.dart';

class PdfExporter {
  PdfExporter._();

  /// 从 data URI 中提取 base64 数据并解码为图片字节。
  /// 格式: data:image/png;base64,iVBOR...
  static Uint8List? _decodeImageFromDataUri(String? dataUri) {
    if (dataUri == null || dataUri.isEmpty) return null;
    try {
      final comma = dataUri.indexOf(',');
      if (comma < 0) return null;
      final base64Str = dataUri.substring(comma + 1);
      return base64Decode(base64Str);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> wrongQuestions(
    List<WrongQuestion> items, {
    Set<int> withAnalysisIds = const {},
    pw.Font? fontOverride,
  }) async {
    final font = fontOverride ?? await PdfGoogleFonts.notoSansSCRegular();
    final pdf = pw.Document();

    for (final item in items) {
      final withAnalysis = withAnalysisIds.contains(item.id ?? 0);
      debugPrint('[PDF] Writing: ${item.questionText.substring(0, item.questionText.length.clamp(0, 50))}');

      final title = item.questionText;
      final meta = '${item.topic ?? ""} · ${item.subTopic ?? ""}   难度: ${"★" * item.difficultyLevel}';
      final imageBytes = _decodeImageFromDataUri(item.questionImagePath);

      final content = <pw.Widget>[
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
          child: pw.Text(title, style: pw.TextStyle(font: font, fontSize: 11)),
        ),
        pw.SizedBox(height: 8),
      ];

      // 有图片则插入图片
      if (imageBytes != null) {
        content.add(pw.Center(
          child: pw.Image(pw.MemoryImage(imageBytes), width: 400, height: 300, fit: pw.BoxFit.contain),
        ));
        content.add(pw.SizedBox(height: 8));
      }

      content.add(pw.Text(meta, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)));

      if (withAnalysis && item.guidanceResultJson != null) {
        content.add(pw.SizedBox(height: 12));
        content.add(pw.Divider());
        content.add(pw.SizedBox(height: 8));
        content.addAll(_analysis(item.guidanceResultJson!, font));
      }

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Padding(
          padding: const pw.EdgeInsets.all(20),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Center(child: pw.Text('错 题 本', style: pw.TextStyle(font: font, fontSize: 16))),
            pw.SizedBox(height: 12),
            pw.Divider(),
            pw.SizedBox(height: 10),
            ...content,
          ]),
        ),
      ));
    }
    return pdf.save();
  }

  static List<pw.Widget> _analysis(String jsonStr, pw.Font font) {
    try {
      final d = json.decode(jsonStr);
      final gr = d is Map ? (d['guidance_result'] ?? d) as Map : {};
      final w = <pw.Widget>[];
      final a = gr['analysis']?.toString() ?? '';
      final s = gr['correct_solution']?.toString() ?? '';
      if (a.isNotEmpty) {
        debugPrint('[PDF] Analysis: ${a.substring(0, a.length.clamp(0, 60))}');
        w.add(pw.Text('题目分析', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)));
        w.add(pw.SizedBox(height: 4));
        w.add(pw.Text(a, style: pw.TextStyle(font: font, fontSize: 10)));
        w.add(pw.SizedBox(height: 8));
      }
      if (s.isNotEmpty) {
        w.add(pw.Text('正确解法', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)));
        w.add(pw.SizedBox(height: 4));
        w.add(pw.Text(s, style: pw.TextStyle(font: font, fontSize: 10)));
      }
      return w;
    } catch (_) {
      return [];
    }
  }

  static Future<void> sharePdf(String name, Uint8List bytes) async {
    await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
  }

  /// 由扫描识别结果（识别文字 + 原图字节）直接生成单页 PDF。
  static Future<Uint8List> scannedPage({
    required String title,
    required String text,
    Uint8List? imageBytes,
  }) async {
    final font = await PdfGoogleFonts.notoSansSCRegular();
    final pdf = pw.Document();
    final content = <pw.Widget>[
      pw.Text(title.isNotEmpty ? title : '扫描识别',
          style: pw.TextStyle(font: font, fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
    ];
    if (imageBytes != null && imageBytes.isNotEmpty) {
      content.add(pw.Center(
        child: pw.Image(pw.MemoryImage(imageBytes), width: 400, height: 300, fit: pw.BoxFit.contain),
      ));
      content.add(pw.SizedBox(height: 8));
    }
    content.add(pw.Text(text.isNotEmpty ? text : '(未识别出文字)',
        style: pw.TextStyle(font: font, fontSize: 11)));
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Padding(
        padding: const pw.EdgeInsets.all(20),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: content),
      ),
    ));
    return pdf.save();
  }

  /// 由题目解析模型的分析过程（[GuidanceResult] 7 段）生成多段 PDF。
  static Future<Uint8List> guidancePdf(GuidanceResult g) async {
    final font = await PdfGoogleFonts.notoSansSCRegular();
    final pdf = pw.Document();
    final children = <pw.Widget>[];
    void add(String title, String body) {
      if (body.isEmpty) return;
      children.add(pw.Text(title,
          style: pw.TextStyle(font: font, fontSize: 12, fontWeight: pw.FontWeight.bold)));
      children.add(pw.SizedBox(height: 4));
      children.add(pw.Text(body, style: pw.TextStyle(font: font, fontSize: 10)));
      children.add(pw.SizedBox(height: 10));
    }

    if (g.title.isNotEmpty) {
      children.add(pw.Text(g.title,
          style: pw.TextStyle(font: font, fontSize: 14, fontWeight: pw.FontWeight.bold)));
      children.add(pw.SizedBox(height: 8));
    }
    add('本题正确答案', g.correctAnswer);
    add('标准分步解析（分析过程）', g.stepAnalysis);
    add('精准错因分析', g.errorAnalysis);
    add('核心知识点回顾', g.knowledgeReview);
    add('本题易错警示', g.warning);
    add('举一反三·变式训练', g.variation);
    if (g.analysis.isNotEmpty) add('题目分析', g.analysis);
    if (g.correctSolution.isNotEmpty) add('正确解法', g.correctSolution);
    if (children.isEmpty) {
      children.add(pw.Text('（无解析内容）',
          style: pw.TextStyle(font: font, fontSize: 10)));
    }
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Padding(
        padding: const pw.EdgeInsets.all(20),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: children),
      ),
    ));
    return pdf.save();
  }
}