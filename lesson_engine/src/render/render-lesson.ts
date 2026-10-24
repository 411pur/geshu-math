import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { safeJsonForScript } from '../lib/json.js';
import type { LessonPlan } from '../schemas/lesson.js';
import type { HtmlRenderer } from '../pipeline/lesson-pipeline.js';

interface KatexAssets { css: string; js: string; version: string; }
let katexAssetsPromise: Promise<KatexAssets> | undefined;

async function loadKatexAssets(): Promise<KatexAssets> {
  if (katexAssetsPromise) return katexAssetsPromise;
  katexAssetsPromise = (async () => {
    const dist = path.join(process.cwd(), 'node_modules', 'katex', 'dist');
    const [css, js, packageRaw] = await Promise.all([
      readFile(path.join(dist, 'katex.min.css'), 'utf8'),
      readFile(path.join(dist, 'katex.min.js'), 'utf8'),
      readFile(path.join(process.cwd(), 'node_modules', 'katex', 'package.json'), 'utf8')
    ]);
    const version = JSON.parse(packageRaw).version as string;
    const fontsDir = path.join(dist, 'fonts');
    const fontUrls = [...new Set([...css.matchAll(/url\(fonts\/([^)]+\.woff2)\)/g)].map((match) => match[1]))];
    const embedded = new Map<string, string>();
    await Promise.all(fontUrls.map(async (file) => {
      const data = await readFile(path.join(fontsDir, file));
      embedded.set(file, `data:font/woff2;base64,${data.toString('base64')}`);
    }));
    const cssWithFonts = css.replace(/url\(fonts\/([^)]+\.woff2)\)/g, (url, file) => `url(${embedded.get(file) || url})`);
    return { css: cssWithFonts, js, version };
  })();
  return katexAssetsPromise;
}

export class LocalHtmlRenderer implements HtmlRenderer {
  constructor(
    private readonly templatePath = path.join(process.cwd(), 'templates', 'teacher-board.html'),
    private readonly clientRendererPath = path.join(process.cwd(), 'src', 'render', 'client-renderer.js')
  ) {}

  async render(plan: LessonPlan): Promise<string> {
    const [template, clientRenderer, katex] = await Promise.all([
      readFile(this.templatePath, 'utf8'),
      readFile(this.clientRendererPath, 'utf8'),
      loadKatexAssets()
    ]);

    const title = escapeHtml(plan.title || '题目讲解');
    const lessonJson = safeJsonForScript(plan);
    const notice = `<!-- KaTeX ${katex.version} (MIT): https://katex.org -->`;

    const html = template
      .replaceAll('__LESSON_TITLE__', () => title)
      .replace('__KATEX_CSS__', () => katex.css)
      .replace('__KATEX_JS__', () => katex.js)
      .replace('__LESSON_JSON__', () => lessonJson)
      .replace('__CLIENT_RENDERER__', () => clientRenderer)
      .replace('</head>', `${notice}\n</head>`);

    if (html.includes('__LESSON_JSON__') || html.includes('__CLIENT_RENDERER__') || html.includes('__KATEX_CSS__') || html.includes('__KATEX_JS__')) {
      throw new Error('模板占位符未完全替换');
    }
    return html;
  }
}

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}
