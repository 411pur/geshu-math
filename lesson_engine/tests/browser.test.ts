import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { chromium, type Browser, type Frame, type Page } from 'playwright-core';
import { LocalHtmlRenderer } from '../src/render/render-lesson.js';
import { PlaywrightVisualAuditor } from '../src/visual/playwright-auditor.js';
import { relayoutOverlappingLabels } from '../src/visual/label-layout.js';
import { createPlan } from './helpers/lesson-fixtures.js';

let browser: Browser;
let page: Page;
let tempDir: string;

beforeAll(async () => {
  const executablePath = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
  browser = await chromium.launch({ executablePath, headless: true });
  tempDir = await mkdtemp(path.join(os.tmpdir(), 'lesson-browser-'));
  const html = await new LocalHtmlRenderer().render(createPlan());
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

describe('generated lesson in Edge', () => {
  it('loads offline and renders the question and controls', async () => {
    expect(await page.locator('#questionText').textContent()).toBe('1 + 1 = ?');
    expect(await page.locator('#optionsGrid .option').count()).toBe(2);
    expect(await page.locator('#playButton').textContent()).toContain('开始上课');
    expect(await page.locator('#topNextButton').textContent()).toContain('下一步');
  });

  it('advances scenes and reveals the final answer', async () => {
    await page.locator('#nextButton').click();
    expect(await page.evaluate(() => (window as any).__LESSON_CURRENT_STEP__)).toBe(1);
    expect(await page.locator('#topStepCounter').textContent()).toBe('2 / 4');
    expect(await page.locator('#formulaBoard').textContent()).toContain('1 + 1 = ?');

    await page.locator('#stepList .step-chip').last().click();
    expect(await page.locator('#stepTitle').textContent()).toBe('得到答案');
    expect(await page.locator('[data-option="B"]').getAttribute('class')).toContain('is-correct');
    expect(await page.locator('[data-option="A"]').getAttribute('class')).toContain('is-wrong');
    expect(await page.locator('#studentFeedback').textContent()).toContain('老师公布答案');
    expect(await page.locator('#topNextButton').isDisabled()).toBe(true);
  });

  it('模拟鼠标会在画布内平滑移动到指点目标', async () => {
    await page.evaluate(() => (window as any).__LESSON_RENDER_STEP__(2));
    await page.waitForTimeout(80);
    const first = await page.evaluate(() => document.getElementById('teacherPointer')!.style.transform);
    await page.waitForFunction((previous) => document.getElementById('teacherPointer')!.style.transform !== previous, first, { timeout: 6000 });
    const second = await page.evaluate(() => document.getElementById('teacherPointer')!.style.transform);
    expect(second).not.toBe(first);
    const inside = await page.evaluate(() => {
      const pointer = document.getElementById('teacherPointer')!.getBoundingClientRect();
      const area = document.getElementById('diagramArea')!.getBoundingClientRect();
      return pointer.x >= area.x - 1 && pointer.y >= area.y - 1 && pointer.right <= area.right + 1 && pointer.bottom <= area.bottom + 1;
    });
    expect(inside).toBe(true);
  });

  it('支持外部播放器通过 postMessage 控制讲课进度', async () => {
    await page.evaluate(() => (window as any).__LESSON_RENDER_STEP__(0));
    await page.evaluate(() => window.postMessage({ __lessonStudio: true, kind: 'play' }, '*'));
    await page.waitForTimeout(80);
    expect(await page.locator('#playLabel').textContent()).toBe('暂停讲课');
    await page.evaluate(() => window.postMessage({ __lessonStudio: true, kind: 'pause' }, '*'));
    await page.waitForTimeout(80);
    expect(await page.locator('#playLabel').textContent()).not.toBe('暂停讲课');
  });

  it('当前步骤矢量加粗，指针高亮在本场景内持续保留', async () => {
    const plan = createPlan();
    plan.diagram.baseElements = [
      { type: 'line', id: 'base-edge', x1: 200, y1: 400, x2: 700, y2: 400, color: 'chalk', dashed: false, width: 2 },
      { type: 'arrow', id: 'vec-a', x1: 300, y1: 400, x2: 300, y2: 220, color: 'pink', dashed: false, label: 'a' },
      { type: 'arrow', id: 'vec-N', x1: 500, y1: 400, x2: 500, y2: 220, color: 'green', dashed: false, label: 'N' }
    ];
    plan.scenes[0].activeElementIds = ['vec-a', 'vec-N'];
    plan.scenes[0].focusPath = [{ x: 300, y: 300 }, { x: 500, y: 300 }];
    plan.scenes[0].durationHintMs = 3000;
    const html = await new LocalHtmlRenderer().render(plan);
    const file = path.join(tempDir, 'stroke.html');
    await writeFile(file, html, 'utf8');
    const probe = await browser.newPage({ viewport: { width: 1280, height: 720 } });
    try {
      await probe.goto(pathToFileURL(file).href);
      await probe.waitForFunction(() => Boolean((window as any).__LESSON_READY__));
      await probe.evaluate('window.__LESSON_RENDER_STEP__(0)');
      const widthOf = (id: string) => probe.evaluate<number>(`(function () { var g = document.querySelector('#diagram [data-element-id="${id}"]'); var s = g && g.querySelector('line,polyline,polygon,rect'); return s ? parseFloat(getComputedStyle(s).strokeWidth) : 0; })()`);
      expect(await widthOf('vec-a')).toBeGreaterThan(await widthOf('base-edge'));
      await probe.waitForTimeout(150);
      await probe.waitForFunction('document.querySelectorAll("#diagram .diagram-element.is-pointed").length >= 2', undefined, { timeout: 20000 });
      expect(await probe.evaluate<number>('document.querySelectorAll("#diagram .diagram-element.is-pointed").length')).toBe(2);
      await probe.waitForTimeout(1500);
      expect(await probe.evaluate<number>('document.querySelectorAll("#diagram .diagram-element.is-pointed").length')).toBe(2);
    } finally { await probe.close(); }
  });

  it('在 1280x720 的小窗口里不产生整页溢出', async () => {
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.evaluate(() => (window as any).__LESSON_RENDER_STEP__(1));
    await page.waitForTimeout(120);
    const overflow = await page.evaluate(() => document.documentElement.scrollHeight - document.documentElement.clientHeight);
    expect(overflow).toBeLessThanOrEqual(0);
    await page.setViewportSize({ width: 1440, height: 900 });
  });
});


describe('嵌入 App 的讲解播放器（iframe）', () => {
  it('宿主 iframe 必须放行 fullscreen，否则子帧的「全屏黑板」会被权限策略拦下', async () => {
    const lessonHtml = await new LocalHtmlRenderer().render(createPlan());
    const dataUrl = `data:text/html;charset=utf-8,${encodeURIComponent(lessonHtml)}`;
    const harness = path.join(tempDir, 'embed-harness.html');
    await writeFile(harness, [
      '<!doctype html><html><body style="margin:0">',
      `<iframe id="blocked" name="blocked" src="${dataUrl}" style="width:640px;height:420px"></iframe>`,
      `<iframe id="allowed" name="allowed" allow="fullscreen" src="${dataUrl}" style="width:640px;height:420px"></iframe>`,
      '</body></html>'
    ].join(''), 'utf8');

    const probe = await browser.newPage({ viewport: { width: 1400, height: 900 } });
    try {
      await probe.goto(pathToFileURL(harness).href);
      await probe.waitForFunction(() => document.querySelectorAll('iframe').length === 2);
      await probe.waitForTimeout(300);
      await probe.evaluate(() => {
        (window as any).__lessonReports = [];
        window.addEventListener('message', (event) => (window as any).__lessonReports.push(event.data));
      });

      const framesByName = new Map<string, Frame>();
      for (const frame of probe.frames()) if (frame !== probe.mainFrame()) framesByName.set(frame.name(), frame);
      expect([...framesByName.keys()].sort()).toEqual(['allowed', 'blocked']);

      const stateOf = (name: string) => {
        const frame = framesByName.get(name);
        if (!frame) throw new Error(`找不到 iframe ${name}`);
        return frame.evaluate(() => ({
          fullscreenEnabled: document.fullscreenEnabled,
          hasToggle: typeof (window as any).__LESSON_TOGGLE_FULLSCREEN__ === 'function'
        }));
      };

      // 没放行的宿主：子帧拿不到全屏权限——这正是 App 里「全屏黑板点了没反应」的原因。
      expect(await stateOf('blocked')).toEqual({ fullscreenEnabled: false, hasToggle: true });
      // 放行之后：子帧拿到全屏权限。
      expect(await stateOf('allowed')).toEqual({ fullscreenEnabled: true, hasToggle: true });

      // 被拦下时不能静默失败：按钮要当场给出反馈，并把原因回传给宿主页面。
      const blockedFrame = framesByName.get('blocked')!;
      await blockedFrame.evaluate(() => (window as any).__LESSON_TOGGLE_FULLSCREEN__());
      await blockedFrame.waitForFunction(() => document.getElementById('fullscreenButton')?.textContent === '全屏被拦截', undefined, { timeout: 5000 });
      await probe.waitForFunction(
        () => ((window as any).__lessonReports as any[]).some((item) => item && item.__lessonStudioStatus === true && item.fullscreen === 'blocked'),
        undefined,
        { timeout: 5000 }
      );
      const report = await probe.evaluate(() => ((window as any).__lessonReports as any[]).find((item) => item && item.fullscreen === 'blocked'));
      expect(String(report.reason)).toContain('权限');
    } finally {
      await probe.close();
    }
  });
  it('标签重叠可以由代码按实测文字框重排修掉（不经过模型）', async () => {
    const plan = createPlan();
    plan.scenes[2].diagramElements = [
      { type: 'point', id: 'p1', x: 400, y: 280, radius: 10, label: 'A', color: 'cyan' },
      { type: 'point', id: 'p2', x: 408, y: 280, radius: 10, label: 'B', color: 'yellow' }
    ];
    const renderer = new LocalHtmlRenderer();
    const auditor = new PlaywrightVisualAuditor();
    const dir = path.join(tempDir, 'overlap');

    const before = await auditor.audit(await renderer.render(plan), plan, { outputDir: dir, iteration: 0 });
    expect(before.issues.some((issue) => issue.code === 'element_overlap')).toBe(true);
    // 测量框是重排的依据：换算到画布坐标后必须落在两个点附近（400/408），不能整体偏掉。
    // 只在“画出数量”这一步看：后面的场景会沿用同一批图元，标签框会重复出现。
    const boxes = before.labelBoxes.filter((box) => box.sceneIndex === 2 && (box.elementId === 'p1' || box.elementId === 'p2'));
    expect(boxes).toHaveLength(2);
    for (const box of boxes) expect(Math.abs(box.x - 418)).toBeLessThan(60);

    const fixed = relayoutOverlappingLabels(plan, before);
    expect(fixed.moved).toBeGreaterThan(0);
    const after = await auditor.audit(await renderer.render(fixed.plan), fixed.plan, { outputDir: path.join(dir, 'after'), iteration: 1 });
    expect(after.issues.filter((issue) => issue.code === 'element_overlap')).toHaveLength(0);
    // 这条用例自己起两个浏览器跑两轮完整审计（5 场景截图 + DOM 测量），
    // 机器上有别的 Edge 在跑时会明显变慢，所以单独给它 90 秒预算。
  }, 90_000);

});

it('数学解答题公布最终答案而不依赖选择题选项', async () => {
  const plan=createPlan({problem:{stem:'解 x²-5x+6=0',options:[],correctOptions:[],sourceAnswer:'',sourceExplanation:'',finalAnswer:'x = 2 或 x = 3'}});
  const html=await new LocalHtmlRenderer().render(plan);
  const file=path.join(tempDir,'free-response.html');await writeFile(file,html,'utf8');
  const target=await browser.newPage();
  try {
    await target.goto(pathToFileURL(file).href);
    await target.waitForFunction(()=>Boolean((window as any).__LESSON_READY__));
    for(let i=0;i<plan.scenes.length-1;i++) await target.locator('#nextButton').click();
    expect(await target.locator('[data-answer-revealed="true"]').textContent()).toContain('x = 2 或 x = 3');
  } finally {await target.close();}
});
