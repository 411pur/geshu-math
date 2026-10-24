import { describe, expect, it, vi } from 'vitest';
import { AppError } from '../src/lib/errors.js';
import {
  documentKindOf,
  extractDocumentText,
  MAX_DOCUMENT_TEXT_CHARS,
  normalizeDocumentText,
} from '../src/pipeline/document-text.js';

// DOCX 分支只验证“确实把字节交给了 mammoth 并把结果规范化”，
// 真实 Word 文件的解析由 mammoth 自己保证（BSD-2，上游自带测试）。
vi.mock('mammoth', () => ({
  default: { extractRawText: vi.fn(async () => ({ value: '从 Word 文档里读到的题干' })) },
}));

/** 生成一份结构完整的单页 PDF（含正确 xref 偏移），用来验证文字层提取。 */
function buildPdf(text: string): Buffer {
  const content = `BT /F1 18 Tf 20 100 Td (${text}) Tj ET`;
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  let pdf = '%PDF-1.4\n';
  const offsets: number[] = [];
  objects.forEach((body, index) => {
    offsets.push(pdf.length);
    pdf += `${index + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xrefOffset = pdf.length;
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets) pdf += `${String(offset).padStart(10, '0')} 00000 n \n`;
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF\n`;
  return Buffer.from(pdf, 'latin1');
}

describe('文档取文', () => {
  it('按扩展名识别类型，其它一律拒绝', () => {
    expect(documentKindOf('题目.PDF')).toBe('pdf');
    expect(documentKindOf('错题/力学.docx')).toBe('docx');
    expect(documentKindOf('笔记.md')).toBe('text');
    expect(documentKindOf('题目.csv')).toBe('text');
    expect(documentKindOf('题图.jpg')).toBeUndefined();
    expect(documentKindOf('没有扩展名')).toBeUndefined();
  });

  it('压掉多余空行，并按题干上限截断', () => {
    const tidy = normalizeDocumentText('第一行  \r\n\r\n\r\n第二行');
    expect(tidy.text).toBe('第一行\n\n第二行');
    expect(tidy.truncated).toBe(false);

    const long = normalizeDocumentText('啊'.repeat(MAX_DOCUMENT_TEXT_CHARS + 50));
    expect(long.text).toHaveLength(MAX_DOCUMENT_TEXT_CHARS);
    expect(long.truncated).toBe(true);
  });

  it('纯文本文件按 UTF-8 读出来', async () => {
    const result = await extractDocumentText('题目.txt', Buffer.from('1 + 1 = ?\n求结果', 'utf8'));
    expect(result).toMatchObject({ kind: 'text', chars: 13, truncated: false });
    expect(result.text).toContain('1 + 1 = ?');
  });

  it('PDF 用 pdf.js 取文字层', async () => {
    const result = await extractDocumentText('题目.pdf', buildPdf('Hello Question'));
    expect(result.kind).toBe('pdf');
    expect(result.pages).toBe(1);
    expect(result.text).toContain('Hello Question');
  });

  it('DOCX 走 mammoth 取纯文本', async () => {
    const result = await extractDocumentText('题目.docx', Buffer.from('zip-bytes'));
    expect(result.kind).toBe('docx');
    expect(result.text).toBe('从 Word 文档里读到的题干');
  });

  it('不支持的类型给出可执行的提示', async () => {
    const error = await extractDocumentText('题图.jpg', Buffer.from('x')).catch((thrown) => thrown);
    expect(error).toBeInstanceOf(AppError);
    expect((error as AppError).code).toBe('unsupported_document');
    expect((error as AppError).message).toContain('只支持 PDF');
    expect((error as AppError).statusCode).toBe(400);
  });
});
