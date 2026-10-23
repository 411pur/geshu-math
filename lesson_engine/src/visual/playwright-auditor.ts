import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { chromium } from 'playwright-core';
import { ConfigurationError } from '../lib/errors.js';
import type { LessonPlan } from '../schemas/lesson.js';
import { auditBrowserSnapshots, calculateScore, type BrowserSceneSnapshot } from './metrics.js';
import { measureLabelBoxes } from './label-layout.js';
import type { VisualAuditContext, VisualAuditor } from './types.js';

const collectSceneSnapshotSource = String.raw`(input) => {
  const rect = (element) => {
    const box = element.getBoundingClientRect();
    return {
      id: element.getAttribute('data-element-id') || element.id || element.className || element.tagName,
      label: element.getAttribute('data-audit-label') || element.id || element.getAttribute('data-element-id') || element.tagName,
      x: box.x, y: box.y, width: box.width, height: box.height,
      clientWidth: element.clientWidth || 0, clientHeight: element.clientHeight || 0,
      scrollWidth: element.scrollWidth || 0, scrollHeight: element.scrollHeight || 0
    };
  };
  const textSelectors = ['#questionText', '.option', '.speech-bubble h2', '.speech-bubble p', '.formula-card', '.tip-card'];
  const textBlocks = textSelectors.flatMap((selector) => Array.from(document.querySelectorAll(selector)).map(rect));
  const diagramArea = document.getElementById('diagramArea');
  const diagram = document.getElementById('diagram');
  const diagramElements = diagram ? Array.from(diagram.querySelectorAll('[data-element-id]')).map(rect) : [];
  const labels = diagram ? Array.from(diagram.querySelectorAll('text.diagram-label')).map((label) => {
    const group = label.closest('[data-element-id]');
    const base = rect(label);
    return { ...base, id: group ? group.getAttribute('data-element-id') : base.id, label: label.textContent || base.id };
  }) : [];
  const pointer = document.getElementById('teacherPointer');
  const finalAnswerRevealed = input.sceneType === 'answer' ? (document.querySelectorAll('.option.is-correct').length > 0 || Boolean(document.querySelector('[data-answer-revealed="true"]'))) : null;
  const hasDiagramImage = Boolean(diagram && diagram.querySelector('image'));
  return {
    sceneIndex: input.sceneIndex,
    sceneType: input.sceneType,
    viewport: { width: window.innerWidth, height: window.innerHeight },
    textBlocks,
    diagramArea: diagramArea ? rect(diagramArea) : undefined,
    diagramElements,
    labels,
    pointer: pointer ? rect(pointer) : undefined,
    optionCount: document.querySelectorAll('#optionsGrid .option').length,
    expectedOptionCount: input.expectedOptionCount,
    finalAnswerRevealed,
    hasDiagramImage,
    pageError: input.pageError
  };
}`;

export class PlaywrightVisualAuditor implements VisualAuditor {
  constructor(private readonly edgeExecutablePath = process.env.EDGE_EXECUTABLE_PATH || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', private readonly viewport = { width: 1600, height: 900 }) {}

  async audit(html: string, plan: LessonPlan, context: VisualAuditContext) {
    await mkdir(context.outputDir, { recursive: true });
    const htmlPath = path.join(context.outputDir, 'lesson.html');
    await writeFile(htmlPath, html, 'utf8');
    let browser;
    try { browser = await chromium.launch({ executablePath: this.edgeExecutablePath, headless: true }); }
    catch (error) { throw new ConfigurationError(`无法启动视觉检查浏览器：${error instanceof Error ? error.message : String(error)}`); }

    try {
      const page = await browser.newPage({ viewport: this.viewport });
      const pageErrors: string[] = [];
      page.on('pageerror', (error) => pageErrors.push(error.message));
      await page.goto(pathToFileURL(htmlPath).href);
      await page.waitForFunction(() => Boolean((window as any).__LESSON_READY__));
      const snapshots: BrowserSceneSnapshot[] = [];
      const screenshots: Array<{ sceneIndex: number; file: string }> = [];
      for (let sceneIndex = 0; sceneIndex < plan.scenes.length; sceneIndex += 1) {
        await page.evaluate((index) => (window as any).__LESSON_RENDER_STEP__(index), sceneIndex);
        await page.waitForTimeout(650);
        const file = `scene-${sceneIndex}.png`;
        await page.screenshot({ path: path.join(context.outputDir, file), fullPage: false });
        screenshots.push({ sceneIndex, file });
        const input = { sceneIndex, sceneType: plan.scenes[sceneIndex].type, expectedOptionCount: plan.problem.options.length, pageError: pageErrors.shift() };
        const snapshot = await page.evaluate(`(${collectSceneSnapshotSource})(${JSON.stringify(input)})`) as BrowserSceneSnapshot;
        snapshots.push(snapshot);
      }
      const report = auditBrowserSnapshots(snapshots, { iteration: context.iteration, screenshots });
      // 标签实测框（换到画布坐标）交给流水线做“按测量结果重排标签”。
      report.labelBoxes = measureLabelBoxes(snapshots, plan.diagram.viewBox || [960, 580]);
      // 同一 id 跨场景复用是合法的“更新同一图元”，只在同一层/同一场景内判重。
      const baseIdList = (plan.diagram.baseElements || []).map((element) => element.id);
      const duplicateIds: string[] = baseIdList.filter((id, index) => baseIdList.indexOf(id) !== index);
      for (const scene of plan.scenes) {
        const sceneIdList = scene.diagramElements.map((element) => element.id);
        duplicateIds.push(...sceneIdList.filter((id, index) => sceneIdList.indexOf(id) !== index));
      }
      const duplicates = [...new Set(duplicateIds)];
      if (duplicates.length) report.issues.push({ code: 'duplicate_element_id', severity: 'warning', sceneIndex: 0, message: `检测到重复图元 ID：${duplicates.join('、')}`, suggestion: '让基础模板和场景使用稳定且唯一的元素 ID', details: {} });
      if (plan.diagram.template && plan.diagram.imageDataUrl) report.issues.push({ code: 'unexpected_image_background', severity: 'critical', sceneIndex: 0, message: '模板模式仍然嵌入了原题截图', suggestion: '移除 imageDataUrl，使用 SVG 模板重绘', details: {} });
      report.score = calculateScore(report.issues);
      report.passed = report.issues.length === 0;
      return report;
    } finally { await browser.close(); }
  }
}
