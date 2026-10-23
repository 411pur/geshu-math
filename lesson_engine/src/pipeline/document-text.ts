import mammoth from 'mammoth';
import { AppError } from '../lib/errors.js';

export type DocumentKind = 'pdf' | 'docx' | 'text';

export interface ExtractedDocument {
  kind: DocumentKind;
  text: string;
  chars: number;
  truncated: boolean;
  pages?: number;
}

/** 与 ProjectInputSchema.text / ProblemExtract 的题干上限保持一致（20000 字）。 */
export const MAX_DOCUMENT_TEXT_CHARS = 20_000;
/** 一道题最多看前 8 页，避免有人丢进来一本教辅。 */
const MAX_PDF_PAGES = 8;

const TEXT_EXTENSIONS = new Set(['txt', 'md', 'markdown', 'csv', 'json', 'log', 'yml', 'yaml']);

export function documentExtension(fileName: string): string {
  const cleaned = (fileName || '').trim().toLowerCase();
  const dot = cleaned.lastIndexOf('.');
  return dot >= 0 ? cleaned.slice(dot + 1) : '';
}

/** 按扩展名判断文件类型；返回 undefined 表示不支持（调用方给出明确提示）。 */
export function documentKindOf(fileName: string): DocumentKind | undefined {
  const extension = documentExtension(fileName);
  if (extension === 'pdf') return 'pdf';
  if (extension === 'docx') return 'docx';
  if (TEXT_EXTENSIONS.has(extension)) return 'text';
  return undefined;
}

/** 统一换行、压掉多余空行并截到上限；截断要显式告诉调用方，别让学生以为文件被完整读取了。 */
export function normalizeDocumentText(raw: string): { text: string; truncated: boolean } {
  const cleaned = (raw || '')
    .replace(/\r\n?/g, '\n')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  return cleaned.length > MAX_DOCUMENT_TEXT_CHARS
    ? { text: cleaned.slice(0, MAX_DOCUMENT_TEXT_CHARS), truncated: true }
    : { text: cleaned, truncated: false };
}

/** 用 pdf.js（Mozilla，Apache-2.0）逐页取文字；只取文字层，扫描件没有文字层时会得到空串。 */
async function extractPdfText(data: Buffer): Promise<{ text: string; pages: number }> {
  const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const document = await pdfjs.getDocument({
    data: new Uint8Array(data),
    isEvalSupported: false,
    disableFontFace: true,
    useSystemFonts: false,
  }).promise;
  const pages = Math.min(document.numPages, MAX_PDF_PAGES);
  const chunks: string[] = [];
  for (let index = 1; index <= pages; index += 1) {
    const page = await document.getPage(index);
    const content = await page.getTextContent();
    chunks.push(content.items.map((item) => ('str' in item ? item.str : '')).join(' '));
  }
  await document.destroy();
  return { text: chunks.join('\n\n'), pages };
}

/**
 * 把上传的文档取成题目文字。
 *
 * 为什么不放在 Flutter 侧：PDF/DOCX 的解析库在 Node 生态里最成熟（pdf.js / mammoth 都是
 * Apache-2.0 / BSD-2 的许可），App 只管把字节传过来——Flutter Web 侧没有可用的等价实现，
 * 硬做会引入商业许可的解析库。
 */
export async function extractDocumentText(fileName: string, data: Buffer): Promise<ExtractedDocument> {
  const kind = documentKindOf(fileName);
  if (!kind) {
    throw new AppError('unsupported_document', '只支持 PDF、Word（.docx）与纯文本（txt/md/csv）三种文件', 400);
  }
  if (kind === 'text') {
    const { text, truncated } = normalizeDocumentText(data.toString('utf8'));
    return { kind, text, chars: text.length, truncated };
  }
  if (kind === 'docx') {
    const result = await mammoth.extractRawText({ buffer: data });
    const { text, truncated } = normalizeDocumentText(result.value || '');
    return { kind, text, chars: text.length, truncated };
  }
  const pdf = await extractPdfText(data);
  const { text, truncated } = normalizeDocumentText(pdf.text);
  return { kind, text, chars: text.length, truncated, pages: pdf.pages };
}
