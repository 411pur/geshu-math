import 'dart:convert';
import 'dart:typed_data';

import 'package:geshu_math/features/lesson_studio/data/lesson_document.dart';
import 'package:flutter_test/flutter_test.dart';

// 说明：不在这里 pump LessonNewPage——它跳转的生成页会带上播放器页，
// 而播放器页依赖 dart:ui_web / package:web，VM 测试编译不过（只有 web 能跑）。
// 页面本身由 `flutter build web`（CI）与真机联调覆盖，这里测不依赖浏览器的部分。

void main() {
  group('文档类型与文本处理', () {
    test('按扩展名判断类型，不支持的返回 null', () {
      expect(lessonDocumentKindOf('题目.PDF'), LessonDocumentKind.pdf);
      expect(lessonDocumentKindOf('错题/力学.docx'), LessonDocumentKind.docx);
      expect(lessonDocumentKindOf('笔记.md'), LessonDocumentKind.text);
      expect(lessonDocumentKindOf('成绩.csv'), LessonDocumentKind.text);
      expect(lessonDocumentKindOf('题图.jpg'), isNull);
      expect(lessonDocumentKindOf('没有扩展名'), isNull);
      expect(lessonDocumentKindOf('结尾是点.'), isNull);
    });

    test('纯文本按 UTF-8 解码，坏字节不至于让整份文件打不开', () {
      expect(decodePlainText(Uint8List.fromList(utf8.encode('1 + 1 = ?'))), '1 + 1 = ?');
      final broken = decodePlainText(Uint8List.fromList([0xE9, 0xFF, 0x41]));
      expect(broken, contains('A'));
    });

    test('文件大小给人看的形式', () {
      expect(formatDocumentSize(900), '1 KB');
      expect(formatDocumentSize(2048), '2 KB');
      expect(formatDocumentSize(3 * 1024 * 1024), '3.0 MB');
    });

    test('文档草稿给出文件名、字数与大小', () {
      const draft = LessonDocumentDraft(
        fileName: '题目.pdf',
        kind: LessonDocumentKind.pdf,
        text: '1 + 1 = ?',
        byteLength: 2048,
      );
      expect(draft.chars, 9);
      expect(draft.summary, '题目.pdf · 9 字 · 2 KB');
    });
  });

  group('素材合并', () {
    test('文档文字排在前面，图片原样带走', () {
      final input = mergeLessonMaterial(
        typedText: '补充：求 a 棒电流方向',
        documentText: '题干：电磁感应双杆……',
        imageDataUrl: 'data:image/png;base64,AAA',
      );
      expect(input.questionText, startsWith('题干：电磁感应双杆……'));
      expect(input.questionText, contains('补充：求 a 棒电流方向'));
      expect(input.imageDataUrl, 'data:image/png;base64,AAA');
      expect(input.hasMaterial, isTrue);
    });

    test('只有空白输入时不算有素材，只有文档时只用文档', () {
      expect(mergeLessonMaterial(typedText: '   ').hasMaterial, isFalse);
      expect(
        mergeLessonMaterial(typedText: '  ', documentText: '只有文档').questionText,
        '只有文档',
      );
      expect(mergeLessonMaterial(typedText: '1 + 1 = ?').questionText, '1 + 1 = ?');
    });
  });
}
