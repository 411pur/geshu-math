import { describe, expect, it } from 'vitest';
import { auditBrowserSnapshots, calculateScore, type BrowserSceneSnapshot } from '../../src/visual/metrics.js';

function baseSnapshot(overrides: Partial<BrowserSceneSnapshot> = {}): BrowserSceneSnapshot {
  return {
    sceneIndex: 0,
    sceneType: 'diagram',
    viewport: { width: 1600, height: 900 },
    textBlocks: [],
    diagramArea: { id: 'diagramArea', label: '画布', x: 0, y: 0, width: 900, height: 580, clientWidth: 900, clientHeight: 580, scrollWidth: 900, scrollHeight: 580 },
    diagramElements: [],
    labels: [],
    pointer: { id: 'pointer', label: '指点', x: 100, y: 100, width: 30, height: 40, clientWidth: 0, clientHeight: 0, scrollWidth: 0, scrollHeight: 0 },
    optionCount: 2,
    expectedOptionCount: 2,
    finalAnswerRevealed: null,
    hasDiagramImage: false,
    ...overrides
  };
}

describe('visual metrics', () => {
  it('detects text overflow and off-canvas elements', () => {
    const report = auditBrowserSnapshots([
      baseSnapshot({
        diagramElements: [{ id: 'far', label: 'far', x: 880, y: 100, width: 80, height: 40, clientWidth: 0, clientHeight: 0, scrollWidth: 0, scrollHeight: 0 }],
        textBlocks: [{ id: 'text', label: 'text', x: 0, y: 0, width: 100, height: 40, clientWidth: 100, clientHeight: 40, scrollWidth: 180, scrollHeight: 40 }]
      })
    ], { iteration: 0, screenshots: [] });
    expect(report.issues.map((issue) => issue.code)).toContain('text_overflow');
    expect(report.issues.map((issue) => issue.code)).toContain('element_out_of_bounds');
    expect(report.passed).toBe(false);
  });

  it('detects overlapping labels', () => {
    const rect = { id: 'a', label: 'A', x: 100, y: 100, width: 80, height: 30, clientWidth: 0, clientHeight: 0, scrollWidth: 0, scrollHeight: 0 };
    const report = auditBrowserSnapshots([baseSnapshot({ labels: [rect, { ...rect, id: 'b', label: 'B', x: 110, y: 105 }] })], { iteration: 0, screenshots: [] });
    expect(report.issues.some((issue) => issue.code === 'element_overlap')).toBe(true);
  });

  it('scores a clean report at 100', () => {
    expect(calculateScore([])).toBe(100);
  });
});
