import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { LocalHtmlRenderer } from '../../src/render/render-lesson.js';
import { PlaywrightVisualAuditor } from '../../src/visual/playwright-auditor.js';
import { createPlan } from '../helpers/lesson-fixtures.js';

const tempDirs: string[] = [];
afterEach(async () => Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true }))));

describe('golden physics visual lesson', () => {
  it('passes a multi-step diagram without layout issues', async () => {
    const outputDir = await mkdtemp(path.join(os.tmpdir(), 'visual-golden-'));
    tempDirs.push(outputDir);
    const plan = createPlan({
      title: '匀强电场中的正六棱柱', subject: '物理',
      problem: {
        stem: '正六棱柱置于匀强电场中，已知各点电势，求正确的说法。',
        options: [{ key: 'A', text: 'φA = 16 V' }, { key: 'B', text: 'φB = 8 V' }, { key: 'C', text: 'E = 1500 V/m' }, { key: 'D', text: 'E = 1700 V/m' }],
        correctOptions: ['A', 'D']
      },
      scenes: [
        { type: 'question', title: '先读题', narration: '同学们，先圈出已知电势。', tip: '先看底面。', formulaLines: [], comparisonRows: [], inspectPanels: [], metricBars: [], diagramElements: [], activeElementIds: [], revealAnswer: false, durationHintMs: 4000 },
        { type: 'formula', title: '找隐藏点', narration: '把 DE 延长一半得到 P 点。', tip: 'PE 等于 DE 的一半。', formulaLines: [{ segments: [{ type: 'text', value: 'PE = 1 cm，φP = 24 V' }] }], comparisonRows: [], inspectPanels: [], metricBars: [], diagramElements: [], activeElementIds: [], revealAnswer: false, durationHintMs: 5000 },
        { type: 'diagram', title: '判断等势线', narration: 'PF 是等势线，EA 和 DB 也是等势线。', tip: '电场线垂直于等势线。', formulaLines: [{ segments: [{ type: 'text', value: 'Ex = 800 V/m' }] }], comparisonRows: [], inspectPanels: [], metricBars: [], diagramElements: [{ type: 'polygon', id: 'hex', points: [{ x: 330, y: 130 }, { x: 610, y: 130 }, { x: 710, y: 290 }, { x: 610, y: 450 }, { x: 330, y: 450 }, { x: 230, y: 290 }], color: 'chalk', fill: 'rgba(255,255,255,0.02)' }, { type: 'line', id: 'pe', x1: 250, y1: 130, x2: 470, y2: 130, color: 'cyan', dashed: true, width: 3 }, { type: 'label', id: 'label-p', x: 250, y: 105, text: 'P', color: 'cyan', size: 24 }, { type: 'label', id: 'label-e', x: 470, y: 105, text: 'E', color: 'chalk', size: 24 }, { type: 'label', id: 'label-d', x: 630, y: 105, text: 'D', color: 'chalk', size: 24 }], activeElementIds: ['hex', 'pe'], focus: { x: 400, y: 160 }, revealAnswer: false, durationHintMs: 6000 },
        { type: 'answer', title: '答案 AD', narration: 'A 和 D 正确。', tip: '1500 只是竖直分量。', formulaLines: [{ segments: [{ type: 'text', value: 'E = 1700 V/m' }] }], comparisonRows: [], inspectPanels: [], metricBars: [], diagramElements: [], activeElementIds: [], revealAnswer: true, durationHintMs: 5000 }
      ]
    });
    const html = await new LocalHtmlRenderer().render(plan);
    const report = await new PlaywrightVisualAuditor().audit(html, plan, { outputDir, iteration: 0 });
    expect(report.issues).toEqual([]);
    expect(report.passed).toBe(true);
    expect(report.screenshots).toHaveLength(4);
  }, 30_000);
});
