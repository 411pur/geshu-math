import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { chromium, type Browser, type Page } from 'playwright-core';
import { LocalHtmlRenderer } from '../src/render/render-lesson.js';
import { createPlan } from './helpers/lesson-fixtures.js';
import type { LessonPlan } from '../src/schemas/lesson.js';

let browser: Browser;
let page: Page;
let tempDir: string;

beforeAll(async () => {
  const executablePath = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
  browser = await chromium.launch({ executablePath, headless: true });
  tempDir = await mkdtemp(path.join(os.tmpdir(), 'lesson-inspect-'));

  const plan = createPlan();
  plan.diagram = { mode: 'svg', viewBox: [960, 580], baseElements: [
    { type: 'rect', id: 'block', x: 400, y: 300, width: 170, height: 100, color: 'cyan', radius: 6 }
  ] };
  plan.scenes.forEach((scene, index) => {
    scene.diagramElements = index === 2 ? [] : [{ type: 'point', id: 'block', x: 485, y: 350, radius: 6, color: 'yellow' }];
    if (index === 2) {
      scene.inspectPanels = [{
        elementId: 'block',
        title: '物块 m = 2 kg',
        forces: [
          { name: '重力 G', magnitude: 20, unit: 'N', direction: '竖直向下' },
          { name: '支持力 N', magnitude: 20, unit: 'N', direction: '竖直向上' }
        ],
        quantities: [{ name: '质量 m', value: 2, unit: 'kg' }]
      }, {
        elementId: 'missing_body',
        title: '隐藏物体（兜底热区）',
        forces: [{ name: '拉力 T', magnitude: 5, unit: 'N', direction: '水平向右' }],
        quantities: []
      }];
      scene.metricBars = [
        { label: '重力 G', value: 20, max: 20, unit: 'N' },
        { label: '支持力 N', value: 20, max: 20, unit: 'N' }
      ];
    }
  });

  const html = await new LocalHtmlRenderer().render(plan);
  const file = path.join(tempDir, 'lesson.html');
  await writeFile(file, html, 'utf8');
  page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(pathToFileURL(file).href);
  await page.waitForFunction(() => Boolean((window as any).__LESSON_READY__));
});

afterAll(async () => {
  await browser?.close();
  if (tempDir) await rm(tempDir, { recursive: true, force: true });
});

describe('inspect panels and metric bars', () => {
  it('renders metric bars in the top-left value board', async () => {
    await page.locator('#stepList .step-chip').nth(2).click();
    await page.waitForTimeout(120);
    const label = await page.locator('#metricBoard .metric-bars-label').textContent();
    expect(label).toBe('实时数值');
    const names = await page.locator('#metricBoard .metric-bar-name').allTextContents();
    expect(names).toEqual(['重力 G', '支持力 N']);
    const values = await page.locator('#metricBoard .metric-bar-value').allTextContents();
    expect(values[0]).toContain('20');
    const fillWidth = await page.locator('#metricBoard .metric-bar-fill').first().evaluate((el) => (el as HTMLElement).style.width);
    expect(fillWidth).toBe('100%');
  });

  it('opens an inspect panel when a clickable diagram element is clicked', async () => {
    await page.locator('#stepList .step-chip').nth(2).click();
    await page.waitForTimeout(120);
    await page.locator('.diagram-element[data-element-id="block"]').click();
    await page.waitForTimeout(80);
    const title = await page.locator('.inspect-panel .inspect-title span').textContent();
    expect(title).toContain('物块');
    const keys = await page.locator('.inspect-panel .inspect-key').allTextContents();
    expect(keys).toContain('重力 G');
    expect(keys).toContain('质量 m');
    const val = await page.locator('.inspect-panel .inspect-val').first().textContent();
    expect(val).toContain('20');
  });

  it('creates a clickable anchor for inspect panels referencing unrendered elements', async () => {
    await page.locator('#stepList .step-chip').nth(2).click();
    await page.waitForTimeout(120);
    const anchors = page.locator('.diagram-element.is-inspect-anchor[data-element-id="missing_body"]');
    expect(await anchors.count()).toBe(1);
    await anchors.click();
    await page.waitForTimeout(80);
    const title = await page.locator('.inspect-panel .inspect-title span').textContent();
    expect(title).toContain('隐藏物体');
    const val = await page.locator('.inspect-panel .inspect-val').first().textContent();
    expect(val).toContain('5');
  });

  it('closes the inspect panel when clicking the close button', async () => {
    await page.locator('.inspect-close').click();
    await page.waitForTimeout(80);
    expect(await page.locator('.inspect-panel').count()).toBe(0);
  });

  it('keeps metric board empty when scene has no metric bars', async () => {
    await page.locator('#stepList .step-chip').last().click();
    await page.waitForTimeout(80);
    expect(await page.locator('#metricBoard .metric-bar').count()).toBe(0);
  });
});
