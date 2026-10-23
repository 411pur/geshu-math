import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { safeJsonForScript } from '../lib/json.js';
import type { LessonPlan } from '../schemas/lesson.js';
import type { HtmlRenderer } from '../pipeline/lesson-pipeline.js';

export class LocalHtmlRenderer implements HtmlRenderer {
  constructor(
    private readonly templatePath = path.join(process.cwd(), 'templates', 'teacher-board.html'),
    private readonly clientRendererPath = path.join(process.cwd(), 'src', 'render', 'client-renderer.js')
  ) {}

  async render(plan: LessonPlan): Promise<string> {
    const [template, clientRenderer] = await Promise.all([
      readFile(this.templatePath, 'utf8'),
      readFile(this.clientRendererPath, 'utf8')
    ]);

    const title = escapeHtml(plan.title || '题目讲解');
    const lessonJson = safeJsonForScript(plan);

    const html = template
      .replaceAll('__LESSON_TITLE__', title)
      .replace('__LESSON_JSON__', lessonJson)
      .replace('__CLIENT_RENDERER__', clientRenderer);

    if (html.includes('__LESSON_JSON__') || html.includes('__CLIENT_RENDERER__')) {
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
