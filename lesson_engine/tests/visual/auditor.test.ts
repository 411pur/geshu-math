import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { LocalHtmlRenderer } from '../../src/render/render-lesson.js';
import { PlaywrightVisualAuditor } from '../../src/visual/playwright-auditor.js';
import { createPlan } from '../helpers/lesson-fixtures.js';

const tempDirs: string[] = [];
afterEach(async () => {
  await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});

describe('PlaywrightVisualAuditor', () => {
  it('captures every scene and passes a clean lesson', async () => {
    const outputDir = await mkdtemp(path.join(os.tmpdir(), 'visual-audit-'));
    tempDirs.push(outputDir);
    const plan = createPlan();
    const html = await new LocalHtmlRenderer().render(plan);
    const report = await new PlaywrightVisualAuditor().audit(html, plan, { outputDir, iteration: 0 });
    expect(report.screenshots).toHaveLength(plan.scenes.length);
    expect(report.issues.some((issue) => issue.severity === 'critical')).toBe(false);
    expect(report.score).toBeGreaterThanOrEqual(80);
  }, 30_000);
});
